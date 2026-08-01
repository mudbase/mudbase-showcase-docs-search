package dev.mudbase.showcase.docssearch;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

/**
 * Mudbase Showcase — Docs Search: a documentation knowledge-base app served by Mudbase
 * (cloud.mudbase.dev) for auth and data, plus a real deployed Mudbase Function for Ask AI
 * retrieval ranking and one server-side Anthropic Claude call for the grounded completion - see
 * plan/build-plan.md "Ask AI architecture" for exactly why that split exists. This Spring Boot +
 * Thymeleaf app is the Java reimplementation of the reference Next.js app at ../web - same
 * Mudbase project, same two collections (documents/search_log), same Function, same RBAC model;
 * see plan/build-plan.md for what deliberately differs (server-rendered forms and a
 * synchronous-in-request-thread Ask AI flow instead of a client-side TanStack Query mutation, and
 * why).
 */
@SpringBootApplication
@ConfigurationPropertiesScan
public class DocsSearchApplication {

  public static void main(String[] args) {
    SpringApplication.run(DocsSearchApplication.class, args);
  }
}
