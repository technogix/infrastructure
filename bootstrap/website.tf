# Repository of the website (Astro + React), published on GitHub Pages.
# Terraform owns the repository and its settings; its content (the site code
# and its publishing workflow) is pushed with git.

resource "github_repository" "website" {
  name        = "website"
  description = "Technogix website (Astro + React), published on GitHub Pages"
  visibility  = "public"

  # Creates main with a README, so that Pages and the ruleset have a branch.
  auto_init = true

  has_issues      = true
  has_discussions = false
  has_projects    = false
  has_wiki        = false

  # Same merge policy as this repository: one squashed commit per pull request.
  allow_merge_commit          = false
  allow_rebase_merge          = false
  allow_squash_merge          = true
  squash_merge_commit_title   = "PR_TITLE"
  squash_merge_commit_message = "PR_BODY"
  delete_branch_on_merge      = true

  # The repository holds the site code and its history: never deleted.
  # Even if prevent_destroy were removed, destroy would only archive it.
  archive_on_destroy = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_repository_vulnerability_alerts" "website" {
  repository = github_repository.website.name
}

# Published by a GitHub Actions workflow of the website repository. The
# custom domain (technogix.dev) is added once the domain is delivered.
resource "github_repository_pages" "website" {
  repository = github_repository.website.name
  build_type = "workflow"
}

# main of the website only changes through a pull request. Required status
# checks are added once the site has its build workflow.
resource "github_repository_ruleset" "website_main" {
  name        = "main"
  repository  = github_repository.website.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true

    pull_request {
      required_approving_review_count = 0
      allowed_merge_methods           = ["squash"]
    }
  }
}
