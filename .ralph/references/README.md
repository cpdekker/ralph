# References Directory

This directory is for reference materials that inform spec creation. Drop files here before running **spec mode** — the AI will analyze them during the research and draft phases.

## What to Include

| Type | Examples | How It's Used |
|------|----------|---------------|
| **Existing Implementations** | `.js`, `.ts`, `.py` files | AI extracts patterns, APIs, and data structures to replicate |
| **Sample Data** | `.csv`, `.json`, `.xml` files | AI understands data formats, field names, and edge cases |
| **Documentation** | `.md`, `.txt`, `.pdf` links | AI incorporates requirements, constraints, and terminology |
| **API Specs** | OpenAPI/Swagger, GraphQL schemas | AI designs compatible interfaces |
| **Screenshots/Wireframes** | `.png`, `.jpg` (describe in a `.md`) | AI understands UI expectations |
| **Meeting Notes** | `.md`, `.txt` | AI captures stakeholder decisions and priorities |

## Usage

1. **Add files** to this directory before running spec mode
2. **Run spec mode**: `node .ralph/run.js <feature-name> spec`
3. The AI will analyze all files here during the **research phase**
4. Reference materials inform the generated spec

## Tips

- **Name files descriptively** — `existing-auth-flow.ts` is better than `code.ts`
- **Add a `_notes.md` file** to explain context for non-obvious files
- **Include only relevant files** — don't dump your entire codebase here
- **Clean up after spec approval** — move/delete files once the spec is finalized

## Example Structure

```
.ralph/references/
├── README.md                    # This file
├── _notes.md                    # Context for the reference files
├── existing-feature.ts          # Code from another repo to replicate
├── sample-output.csv            # Expected data format
├── api-documentation.md         # External API docs
└── requirements-from-pm.md      # Stakeholder requirements
```

## What NOT to Include

- Sensitive credentials or secrets
- Large binary files (videos, compiled assets)
- Entire codebases — pick specific relevant files
- Files already in your repo (the AI reads the codebase directly)
