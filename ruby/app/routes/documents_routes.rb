# frozen_string_literal: true

# Document library + CRUD. Read is granted to every visitor including the silent anonymous
# guest (see SessionHelpers#with_read_token); create/update/delete require a real signed-in
# "customer" account, with edit/delete additionally scoped to the document's own `authorId` by
# this app's own `require_owner!` gate below - Mudbase's single default role grants full CRUD to
# any signed-in customer, so per-document ownership isn't enforced by the collection permission
# itself, only by this app (mirrors the reference web app's `isOwner` check in
# `src/app/documents/[id]/page.tsx` and `.../edit/page.tsx`).
class App < Sinatra::Base
  TITLE_MAX_LENGTH = 200
  CONTENT_MAX_LENGTH = 50_000
  TAGS_MAX_LENGTH = 500

  # Document library: server-side substring search across title/content/tags (this app has no
  # client-side JavaScript at all, so the reference web app's client-side `matchesSearchTerm`
  # filter runs here instead, against the `q` query param) - matches `lib/retrieval.rb`.
  get "/" do
    documents = with_read_token { |token| Mudbase::DocumentsRepo.all(access_token: token) }
    @search_term = params["q"].to_s
    @documents = documents.select { |document| Retrieval.matches_search_term?(document, @search_term) }
    erb :"documents/index"
  end

  get "/documents/new" do
    require_login!
    @document = { title: "", content: "", tags: "" }
    @form_action = "/documents"
    @form_title = "New document"
    @submit_label = "Publish document"
    erb :"documents/form"
  end

  post "/documents" do
    require_login!

    values = extract_document_form(params)
    errors = validate_document_form(values)
    if errors.any?
      @document = values
      @form_action = "/documents"
      @form_title = "New document"
      @submit_label = "Publish document"
      show_error_now(errors.join(" "))
      halt erb(:"documents/form")
    end

    created = with_access_token do |token|
      Mudbase::DocumentsRepo.create!(
        access_token: token,
        attributes: document_attributes(values).merge(
          authorId: @current_user[:id],
          authorName: actor_display_name,
        ),
      )
    end

    flash_notice("Document published.")
    redirect "/documents/#{created[:_id]}"
  end

  get "/documents/:id" do
    document = with_read_token { |token| Mudbase::DocumentsRepo.find(access_token: token, id: params["id"]) }
    halt 404, erb(:"errors/not_found", layout: :layout) unless document

    @document = document
    @tags = parse_tags(document[:tags])
    erb :"documents/show"
  end

  get "/documents/:id/edit" do
    require_login!

    document = with_access_token { |token| Mudbase::DocumentsRepo.find(access_token: token, id: params["id"]) }
    halt 404, erb(:"errors/not_found", layout: :layout) unless document
    unless owner_of?(document)
      flash_error("You can only edit documents you authored.")
      redirect "/documents/#{document[:_id]}"
    end

    @document = document
    @form_action = "/documents/#{document[:_id]}"
    @form_title = "Edit document"
    @submit_label = "Save changes"
    erb :"documents/form"
  end

  post "/documents/:id" do
    require_login!

    document = with_access_token { |token| Mudbase::DocumentsRepo.find(access_token: token, id: params["id"]) }
    halt 404, erb(:"errors/not_found", layout: :layout) unless document
    unless owner_of?(document)
      flash_error("You can only edit documents you authored.")
      redirect "/documents/#{document[:_id]}"
    end

    values = extract_document_form(params)
    errors = validate_document_form(values)
    if errors.any?
      @document = document.merge(values)
      @form_action = "/documents/#{document[:_id]}"
      @form_title = "Edit document"
      @submit_label = "Save changes"
      show_error_now(errors.join(" "))
      halt erb(:"documents/form")
    end

    with_access_token do |token|
      Mudbase::DocumentsRepo.update!(access_token: token, id: document[:_id], attributes: document_attributes(values))
    end

    flash_notice("Document updated.")
    redirect "/documents/#{document[:_id]}"
  end

  post "/documents/:id/delete" do
    require_login!

    document = with_access_token { |token| Mudbase::DocumentsRepo.find(access_token: token, id: params["id"]) }
    halt 404, erb(:"errors/not_found", layout: :layout) unless document
    unless owner_of?(document)
      flash_error("You can only delete documents you authored.")
      redirect "/documents/#{document[:_id]}"
    end

    with_access_token { |token| Mudbase::DocumentsRepo.delete!(access_token: token, id: document[:_id]) }
    flash_notice("Document deleted.")
    redirect "/"
  end

  helpers do
    def extract_document_form(params)
      {
        title: params["title"].to_s.strip,
        content: params["content"].to_s,
        tags: params["tags"].to_s.strip,
      }
    end

    def validate_document_form(values)
      errors = []
      errors << "Title is required." if values[:title].empty?
      errors << "Title is too long." if values[:title].length > TITLE_MAX_LENGTH
      errors << "Content is required." if values[:content].empty?
      errors << "Content is too long." if values[:content].length > CONTENT_MAX_LENGTH
      errors << "Tags are too long." if values[:tags].length > TAGS_MAX_LENGTH
      errors
    end

    def document_attributes(values)
      { title: values[:title], content: values[:content], tags: values[:tags] }
    end
  end
end
