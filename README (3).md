# RigRota — standalone legal information site (review before publishing)

This ZIP contains ONLY static HTML/CSS files and no live RigRota application code, customer data, API keys or backend connections.

## IMPORTANT approval and compliance checks
- These are newly prepared drafts using information supplied by Robbie and descriptions of staging features. They are NOT a copy of the latest owner-approved Lovable pages and are NOT verified legal advice.
- Robbie must review and approve final wording before publication, especially the actual service provider list, transfers outside the UK, lawful bases, retention, consumer terms and subscription terms. Review against the current production app, which may differ from staging.
- Confirm that support@rigrota.co.uk receives mail, that identity-verification and safe manual deletion processing actually exist, and that staff can process deletion requests. Do NOT use the unsafe backend delete function.
- Google Play requires a discoverable in-app path to request deletion PLUS an external web resource. The current app's hidden/disabled Delete Account button is not sufficient. Link Settings to the supported request page/email and test in a subsequent app build.
- The date is 31 October 2026; update it if final publication happens on another date.
- Note legal pages should ideally be controlled by Robbie/RigRota; don't place long-term legal content solely under the freelancer's account without his agreement.

## Publish without changing the live RigRota code or installing Mac software
1. Create a NEW PUBLIC GitHub repository owned/controlled by Robbie (e.g. `rigrota-legal-pages`). Do not make the STAGING repo public.
2. Unzip this package on your Mac. Upload index.html, styles.css and all four folders with their index.html files to the NEW repo's root, using GitHub's Add file > Upload files. Keep folder structure.
3. In that new repo: Settings > Pages > Build and deployment > Deploy from a branch > main / (root) > Save.
4. GitHub Pages will show the actual published address after deployment, typically https://OWNER.github.io/REPOSITORY/privacy/ and /delete-account/. Do not guess URLs; open and verify them in a private browser window.
5. Enter the verified privacy URL into Google Play Console; use the working /delete-account/ URL in the App account deletion field. Ensure in-app links also work and complete all data-safety disclosures before submission.
6. If Robbie can manage rigrota.co.uk DNS, configure an approved custom domain with the host, or link to these public legal pages from the existing website. This is optional if the GitHub Pages URLs work, but owner-owned branding is preferred.

For review only: editing HTML does not affect the production app or database.
