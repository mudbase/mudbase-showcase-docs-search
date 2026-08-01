# frozen_string_literal: true

# Ask AI - the actual point of this showcase. See plan/build-plan.md "Ask AI architecture" for
# the full, source-cited rationale. Short version: a real, deployed Mudbase Function
# (`docsAskRetrieval`) does keyword-overlap retrieval ranking inside its network-isolated
# sandbox and returns a grounded context block + citations; this route then makes the one call
# the sandbox is structurally incapable of making itself - the LLM completion call
# (`lib/llm/anthropic_client.rb`) - because a Mudbase Function's `isolated-vm` sandbox has zero
# network access, full stop, regardless of what env var it holds.
#
# Available to guests (read-only) and signed-in users alike, matching this project's RBAC:
# anonymous/guest browsing+search is read-only, so a guest can ask a question and read the
# answer, but `search_log` entries are only written for a real signed-in user (never a
# placeholder `userId`) - see `log_search` below.
class App < Sinatra::Base
  QUESTION_MAX_LENGTH = 2000
  CANDIDATE_LIMIT = 5

  get "/ask" do
    @question = ""
    @recent_searches = with_read_token { |token| Mudbase::SearchLogRepo.recent(access_token: token) }
    erb :"ask/index"
  end

  post "/ask" do
    @question = params["question"].to_s.strip

    if @question.empty? || @question.length > QUESTION_MAX_LENGTH
      show_error_now(@question.empty? ? "Enter a question." : "Keep the question under #{QUESTION_MAX_LENGTH} characters.")
      @recent_searches = with_read_token { |token| Mudbase::SearchLogRepo.recent(access_token: token) }
      halt erb(:"ask/index")
    end

    documents = with_read_token { |token| Mudbase::DocumentsRepo.all(access_token: token) }
    scored = Retrieval.score_documents(documents, @question)

    if scored.empty?
      @no_match = true
      log_search(result_count: 0)
    else
      candidates = Retrieval.top_candidates(scored, limit: CANDIDATE_LIMIT)
      run_ask_flow(candidates)
    end

    @recent_searches = with_read_token { |token| Mudbase::SearchLogRepo.recent(access_token: token) }
    erb :"ask/index"
  end

  helpers do
    # Invokes the Mudbase Function, then (only if it found something to ground an answer in)
    # the LLM completion call - mirrors `POST /api/ask` in the reference Next.js app exactly,
    # including its "usedCount === 0" canned-response short-circuit that skips the LLM call
    # entirely rather than asking it to answer from nothing.
    def run_ask_flow(candidates)
      retrieval = Mudbase::FunctionClient.invoke_retrieval(question: @question, candidates: candidates)

      if retrieval.used_count.zero?
        @answer = "I couldn't find anything in the knowledge base closely related to that question. " \
          "Try rephrasing, or add a document that covers it."
        @citations = []
        log_search(result_count: 0)
        return
      end

      @answer = Llm::AnthropicClient.generate_grounded_answer!(question: @question, context_block: retrieval.context_block)
      @citations = retrieval.citations
      log_search(result_count: @citations.length)
    rescue Mudbase::FunctionError, Llm::LlmError => e
      # Never fabricate an answer on failure - surface the real error (e.g. the Mudbase Function
      # couldn't be reached, or "ANTHROPIC_API_KEY is not configured") exactly like the
      # reference web app's `POST /api/ask` returning a 502 with that same message. No
      # search_log entry is written for a failed attempt, matching the reference app (its
      # search_log write only happens after a successful askAI.mutateAsync resolves).
      @ask_error = e.message
    end

    # Only written for a real signed-in user - `userId` must be a real ObjectId or omitted
    # entirely, never a placeholder, and this project's RBAC grants guests read-only access, so
    # a guest's search is answered but not logged.
    def log_search(result_count:)
      return unless logged_in?

      attributes = {
        queryText: @question,
        resultCount: result_count,
        userId: @current_user[:id],
        userName: actor_display_name,
      }
      with_access_token { |token| Mudbase::SearchLogRepo.create!(access_token: token, attributes: attributes) }
    end
  end
end
