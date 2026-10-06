# 0009. Sites on GitHub Pages, one module instance each

Date: 2026-10-06

## Context

The website is Astro + React, hence static. OVHcloud web hosting costs money and has no Terraform resource; Object Storage static hosting has no HTTPS on a custom domain, which `.dev` requires. Another site is more likely than another domain.

## Decision

`modules/github-pages-site`: repository (never deleted), ruleset, GitHub Pages published by a workflow, and the site's own DNS records (apex or subdomain). `stacks/website` instantiates it for each site of `terraform.tfvars.json`.

## Consequences

- The custom domain and HTTPS enforcement only apply once Pages exists: the deploy job applies until convergence.
- The site content and its publishing workflow live in each site repository.
