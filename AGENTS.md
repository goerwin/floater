# AGENTS.md

## Chat

- Answer in the language of the user's current prompt unless instructed otherwise.
- Never use the em dash ('—'). Use a hyphen ('-') instead.
- Be concise. Do not expand explanations more than necessary.
- Prefer straight apostrophes (') over typographic apostrophes (’) in contractions and possessives (e.g. I'm, we're, user's).

Shortcuts (always respond using a Writing Block with `variant="standard"`):

- `fg:` or `fg` - Provide feedback on whether the following text is well written. Keep the response in the same language, improve naturalness and clarity, and preserve the original meaning.
- `tr:` or `tr` - Translate the following text into English if it is in Spanish, or into Spanish otherwise. Include brief examples or usage context when helpful.
- `def:` or `def` - Explain the meaning of the following word or expression in the same language, ideally with examples.
- `re:` or `re` - Provide multiple natural ways to express the given word, phrase, or idea. First, show alternatives in the original language, then provide equivalent expressions in the other language. Include brief notes on nuance, tone, or common usage when helpful.

## Work

- Use plain, natural language when replying and writting. Avoid complex or hard-to-follow wording. Aim for an “explain it like I’m 5” approach while keeping it professional.
- Treat the prompt as transcribed text from a speech-to-text app, so some terms may be inaccurate or misleading. If it's confusing, ask the user for clarification.
- Write commit messages using Conventional Commits (e.g. `feat: ...`). Keep them to 1 or 2 short lines. Avoid additional descriptions unless strictly necessary, and never add anyone as a co-author.
- When creating new branches, use conventional branch names (e.g. `feat/calendar`, `fix/button`, `chore/tooling...`).
- When fixing a bug, first reproduce it in an end-to-end scenario that closely matches how an end user experiences it. Base the fix on the reproduced behavior.
- Add comments only when they explain something the code does not make clear. Keep them concise, and follow project conventions for code documentation (e.g. JSDoc).
- Update documentation only when needed to keep it accurate or explain relevant usage. Keep it concise and omit unnecessary implementation details.
- Point out incorrect assumptions, mistakes, or misunderstandings when they affect the solution. Do not validate incorrect conclusions.
- When making technical decisions, prioritize correctness, simplicity, robustness, scalability, and long-term maintainability over implementation effort, unless the user explicitly asks for the quickest or lowest-cost solution.
- Preserve the user's existing coding style unless there is a clear reason to change it.
- Keep changes focused. Avoid unrelated refactors or drive-by improvements unless they are necessary to implement the requested change.
- Avoid duplicating logic, component structure, or styles. Prefer reusage. Extract shared code when duplication is intentional and likely to be maintained together, but do not introduce unnecessary abstractions for one-off cases.

## Architecture

- Follow the existing structure of the project. These rules are the default for new projects or areas without a clear convention.
- Organize code by feature, not by file type. A feature folder holds everything it needs: UI, state, logic, data access, types, and tests.
- Code used by only one feature stays inside that feature. Code shared by several features can live at the root (e.g. `ui/`, `utils/`) or in a common parent folder.
- Dependencies point one way: `app` -> `features` -> shared (`ui`, `lib`, `utils`). Shared code never depends on features.
- Features don't use another feature's internals. Use only what the feature exposes as its public API, or move the shared part out.
- `ui/` holds presentational, stateless components: inputs in, events out. No data fetching, business logic, or app state.
- `utils/` holds small, pure, generic functions with no domain knowledge. Feature-specific helpers stay inside their feature.
- Keep tests next to the code they test when the platform allows it. Otherwise, mirror the source structure in the test folder.
- Match the project's existing naming style for folders and files (e.g. `PascalCase` in Swift, `kebab-case` in many web projects). For new projects, use the platform's most common convention.

Example (names and casing are only a guide):

```
app/          # entry point, navigation, dependency wiring
features/
  calendar/   # UI, state, logic, and tests for the calendar
  settings/
ui/           # shared presentational components (Button, Card...)
lib/          # adapters for external services (api, storage, auth)
utils/        # small generic helpers (date, format...)
```

### Before writing or changing code

- Search for existing code that already does what you need (UI components, logic, utils, types). Reuse or extend it instead of creating a near-duplicate.
- Decide where the code belongs before writing it.
- If code you touch is now in the wrong place, duplicated, or needed by more than one feature, move or refactor it as part of the change. This is an exception to "Keep changes focused", but only for the code your change touches. Suggest bigger restructures instead of doing them.
- After the change, remove anything left unused (exports, files, styles, tests).

### Dependencies and testability

- Keep business logic in plain functions or classes that don't depend on the UI framework or I/O.
- Use ports and adapters (hexagonal architecture) at I/O boundaries: network, storage, auth, time, randomness, platform APIs. Define an interface (or protocol) for what the feature needs, implement it in an adapter, and inject it (e.g. constructor, function params, props, or environment).
- In tests, swap adapters for simple in-memory fakes instead of mocking modules or internals.
- Don't add interfaces around pure logic or internal code. Abstractions should enable testing or swapping, not add ceremony.

### Testing

- Follow the platform's best practices and official guides for structure and testing.
- Test behavior the way a user experiences it, not implementation details. Interact with the UI like a user and find elements by what they see, such as roles, labels, or text (e.g. React Testing Library with `user-event`, or XCUITest with accessibility labels).
- Don't assert on internal state, private functions, or view structure. A refactor that keeps behavior the same should not break tests.
- Mock only at the edges (adapters, network), never the code under test.
- If something is hard to test this way, treat it as a design problem and fix the structure, not the test.
- Add a regression test when a bug fix changes real behavior that could break again. Skip it for small tweaks or changes that don't affect behavior.

## Development

- Work in the `main` branch unless told otherwise
- When you need to test the app, close the current app if its running and replace it with the new one to test
- Avoid duplicating logic, component structure, or styles. Extract shared code when duplication is intentional and likely to be maintained together, but do not introduce unnecessary abstractions for one-off cases.
- Keep changes focused. Avoid unrelated refactors or drive-by improvements unless they are necessary to implement the requested change.
