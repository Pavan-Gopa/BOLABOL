# GEMINI.md

## Project Overview

This is a desktop application named **SmartScribe**, built with Electron, React, and TypeScript. It functions as a voice note and transcription tool, offering both local and cloud-based transcription services.

The application leverages:
- **Electron** as the application framework.
- **React** and **TypeScript** for the user interface.
- **Vite** for the frontend build process.
- **Whisper.cpp** via `@kutalia/whisper-node-addon` for local, on-device transcription.
- **Google Gemini** and **OpenAI Whisper** for cloud-based transcription.
- **Google Gemini** for "polishing" and refining the transcribed text.

The architecture consists of a main Electron process (`main.js`), a React-based renderer process (`index.tsx`), and a separate forked process (`transcription.fork.js`) for handling CPU-intensive transcription tasks without blocking the main thread.

## Building and Running

The following scripts are available in `package.json` to build and run the application:

- **`npm run start`**: This command compiles the TypeScript code, builds the Vite project, and then starts the Electron application in development mode.

- **`npm run build`**: This command builds a distributable installer for Windows.

- **`npm run build:mac`**: This command builds a distributable installer for macOS.

- **`npm run build:linux`**: This command builds a distributable installer for Linux.

- **`npm run pack`**: This command packages the application into a directory without creating an installer.

## Development Conventions

- The project is written in **TypeScript**.
- The user interface is built with **React**.
- **CSS** is used for styling.
- Logging is handled by **`electron-log`**.
- **`electron-builder`** is used to create installers for different operating systems.
- The application uses a multi-process architecture to ensure a responsive user interface.
- API keys and other sensitive information are managed through a `.env.local` file and accessed via `process.env`.
