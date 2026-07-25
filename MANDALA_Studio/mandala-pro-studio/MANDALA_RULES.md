# MANDALA Pro Studio: Workflow & Build Rules

This document outlines the mandatory development and verification cycle for all code changes, additions, and updates inside the MANDALA Pro Studio application.

## 1. The Build & Test Rule
> [!IMPORTANT]
> **Always trigger a new build and test cycle after ANY code modification, tool introduction, or feature addition.**
>
> 1. **Close the active development/build session** (stop the current running process or dev server if applicable).
> 2. **Build the project cleanly** (e.g. check TypeScript compiler and Vite bundles).
> 3. **Launch the new build / dev server** to load the fresh code.
> 4. **User validation**: The user will interactively test the new feature, brush style, synthesizer, or AI tool. If anything is unsatisfactory, the user will write feedback to initiate the next iteration.

## 2. Code Quality & Integration Standards
- Maintain high devicePixelRatio crispness across all screen boundaries (Retina screens support).
- Guarantee zero audio lag/blockage in the Web Audio API synthesizer.
- Protect the Gemini API Key by only accessing it client-side through local storage or environment variables.
- Preserve undo/redo stack compatibility whenever new drawing structures are introduced.
