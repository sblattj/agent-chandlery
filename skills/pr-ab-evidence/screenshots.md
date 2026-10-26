# Before/after UI screenshots via a throwaway Vite + Playwright harness

For a UI bug-fix PR, capture real before/after images WITHOUT standing up the full
authenticated app. Mount the single changed component in a standalone Vite page, stub its
data, and screenshot it with Playwright (already a dep: `@playwright/test`). Run once with
the fix (B), once with the production reverted (A) - same harness, only production changes.

No new deps, no Storybook, no vitest-browser. Works because `@/test/render` shows the
components only need light providers (`QueryClientProvider` + `TooltipProvider`, and
`RouterProvider` only if the component reads the router).

## Recipe

Do this inside a per-PR worktree's frontend package dir (install first if fresh, e.g.
`pnpm install --frozen-lockfile` plus any codegen step). Put throwaway files at that package
root and delete them after.

1. **Find the global Tailwind CSS** the app entry imports and import it in the harness, or
   badges/styles won't render: `grep -n "\.css" src/main.tsx`.

2. **`ab-shot.html`** at the package root:
   ```html
   <!doctype html><html><head><meta charset="utf-8"><title>ab</title></head>
   <body style="margin:0;padding:24px;background:#fff">
   <div id="root" style="max-width:560px"></div>
   <script type="module" src="/ab-shot.tsx"></script></body></html>
   ```

3. **`ab-shot.tsx`** - import the global CSS; stub data; mount the real component in
   providers. Prefer stubbing `window.fetch` (simplest) for a react-query component:
   ```tsx
   import "./src/index.css"; // the path you grep'd
   import { createRoot } from "react-dom/client";
   import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
   import { TooltipProvider } from "@/components/ui/tooltip";
   import { TheComponent } from "@/components/...";
   const real = window.fetch.bind(window);
   window.fetch = async (i, init) => {
     const url = typeof i === "string" ? i : i.url;
     if (url.includes("/the-endpoint")) return new Response(JSON.stringify(DATA),
       { status: 200, headers: { "content-type": "application/json" } });
     return real(i, init);
   };
   const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
   createRoot(document.getElementById("root")!).render(
     <QueryClientProvider client={qc}><TooltipProvider>
       <TheComponent {...propsFromTheFailingTest} />
     </TooltipProvider></QueryClientProvider>);
   ```
   For a component with a full interaction flow (many endpoints), reuse the existing
   component test's mocks: either lift its handlers into an `msw/browser` worker
   (`pnpm exec msw init public/ --save`, `setupWorker(...handlers).start()`), or fetch-stub
   each payload. Read the test file to learn the exact scenario and props.

4. **`ab-shot.mjs`** - Playwright runner:
   ```js
   import { chromium } from "@playwright/test";
   const [,, url, out] = process.argv;
   const b = await chromium.launch();
   const p = await b.newPage({ viewport: { width: 600, height: 820 }, deviceScaleFactor: 2 });
   await p.goto(url, { waitUntil: "networkidle" });
   // drive any interaction the bug needs, e.g.:
   // await p.getByLabel("Query Parameters").fill("page=2");
   // await p.getByRole("button", { name: /execute/i }).click();
   await p.waitForTimeout(600);
   await p.locator("#root").screenshot({ path: out });
   await b.close();
   ```

5. **Serve + shoot.** Copy the `VITE_*` env vars from the `dev` npm script (avoids
   import-time env errors), run vite in the background:
   `<VITE_ vars> pnpm exec vite --mode development --port 5199 --strictPort`.
   - B (fix): `node ab-shot.mjs "http://localhost:5199/ab-shot.html" .../B-fixed.png`
   - A (bug): revert the production fix (file checkout to base, or surgical hunk - same rule
     as the red/green leg), let vite HMR reload, `node ab-shot.mjs ... .../A-bug.png`
   - Restore production; delete harness files; confirm `git status --short` clean.

## Gotchas

- **Token-gated fetch** → if the component resolves a Keycloak/bearer token before its
  request, a plain `window.fetch` stub errors (the token path fails first) and data never
  loads. Instead seed the react-query cache directly with the exact query key, e.g.
  `queryClient.setQueryData(["listTemplateKeys"], CATALOG)` - deterministic and
  network-free. Find the key in the component's query hook.
- Import-time env errors → you didn't pass the `VITE_*` vars; copy them from `dev`.
- Unstyled/naked badges → the global CSS import path is wrong.
- Blank component → it needs the router; wrap in a memory `RouterProvider` like
  `renderWithRouter` in `src/test/render.tsx`.
- Collapsible/accordion panels may render collapsed → click the trigger before screenshot.
- Keep viewport tight and `deviceScaleFactor: 2` for crisp, readable images.

## Attaching to the PR (proven CDP browser recipe)

Private-repo PR comments won't render raw-URL images (camo can't auth). Upload the PNGs as
native GitHub attachments via a browser driven over CDP (tool names below are from a CDP
MCP server; any driver with type, upload and evaluate works) - this exact flow worked on the
classic PR page:

1. Confirm a browser is on the debug port and logged into GitHub as the write-access user:
   `take_snapshot` of `https://github.com` shows the user menu / avatar. (`evaluate_script`
   returns empty inline - results go to its `savePath` file; **the expression must be an
   invoked IIFE `(() => {...})()`, a bare arrow `() => ...` returns the function un."**)
2. `activate` the `input` group (gives `upload_file`).
3. Navigate to the PR conversation page. The classic comment form has stable ids:
   textarea `#new_comment_field`, its attach input `#fc-new_comment_field`, submit
   `form.js-new-comment-form button.btn-primary.btn[type=submit]`. (Other `input[type=file]`
   on the page are inline review-reply forms - never target those.)
4. `type_text` (selector `#new_comment_field`) the intro + "**A - ... (bug):**" caption
   ending in a newline. `upload_file` (selector `#fc-new_comment_field`) with `[A.png]`.
   Poll `evaluate_script` reading `document.getElementById('new_comment_field').value` until
   it contains `user-attachments` and not `Uploading`. GitHub inserts an `<img ...>` tag.
5. `type_text` the "**B - ... fix:**" caption, `upload_file` `[B.png]`, poll until 2 assets
   present and nothing "Uploading".
6. `click` the submit selector. Verify with
   `gh api repos/<owner>/<repo>/issues/<n>/comments --jq '...scan("user-attachments/assets/...")'`
   and check the imgs' `naturalWidth>0` (they proxy through
   `private-user-images.githubusercontent.com`).

If the browser isn't logged into GitHub, ask the user rather than publishing internal UI to
a public host (e.g. a public gist).
