# Yum Chase static site example

The static site now lives in the repository-level `pages/` directory:

- `pages/index.html` is the About home page.
- `pages/privacy.html` is the Privacy page.
- `pages/site.css` and `pages/assets/` are the pages' local styles and images.

From the repository root, preview it with:

```sh
python3 -m http.server 8000 --directory pages
```

The repository deploys `pages/` with GitHub Actions. On first setup, set
Settings → Pages → Build and deployment → Source to **GitHub Actions**. The
workflow deploys on pushes to `master` that change `pages/` or the workflow.

The Privacy page is a release-review draft. Confirm the policy owner, support
contact, service-provider retention terms, and effective date before release.
The App Store destination is omitted until the listing URL is known.
