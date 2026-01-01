# Jac Dev Command Architecture

## Overview

The `jac dev` command provides a development-optimized server setup with hot-reload capabilities for Jac applications. It automatically splits your application into frontend and backend servers running on consecutive ports, with intelligent file watching that reloads only the affected server when changes are detected.

## High-Level Architecture

### Dual-Server Model

The `jac dev` command runs two separate server processes:

1. **Frontend Server** (port N): Handles user-facing content
   - Static files (HTML, CSS, JavaScript, images, fonts)
   - Client-side Jac files (`.cl.jac`)
   - Frontend routing and page serving
   - Proxies API requests to the backend server

2. **Backend Server** (port N+1): Handles application logic
   - REST API endpoints (functions and walkers)
   - Authentication and authorization
   - Business logic in `.jac` and `.py` files
   - Data persistence and processing

### Port Assignment

By default:
- Frontend server: Port 8000
- Backend server: Port 8001

Users can customize the base port using `--port`, which automatically calculates the backend port as `base_port + 1`.

### Process Management

The command spawns two independent server processes:

1. Each server runs the `jac serve` command with a `--mode` parameter
2. Frontend mode: `jac serve app.jac --mode frontend --port 8000`
3. Backend mode: `jac serve app.jac --mode backend --port 8001`
4. Both processes share the same application code but serve different endpoints

### File Watching System

The command uses a file watcher (watchfiles library) to monitor the project directory for changes:

**Frontend-triggering files:**
- Client-side Jac files: `.cl.jac`
- Web assets: `.html`, `.htm`, `.css`
- JavaScript/TypeScript: `.js`, `.jsx`, `.ts`, `.tsx`
- Images: `.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`, `.ico`, `.webp`
- Fonts: `.woff`, `.woff2`, `.ttf`, `.otf`, `.eot`

**Backend-triggering files:**
- Server-side Jac files: `.jac` (excluding `.cl.jac`)
- Python files: `.py`

### Intelligent Reload Strategy

When a file change is detected:

1. **Categorization**: The system determines if the file is frontend or backend
2. **Selective Reload**: Only the affected server is restarted
3. **Graceful Shutdown**: The old process is terminated with a 2-second timeout
4. **Process Spawn**: A new server process is started with the same configuration
5. **State Preservation**: Session data and persistent state remain intact

This selective approach means:
- Changing a CSS file only restarts the frontend (fast)
- Changing a Jac backend file only restarts the backend (preserves frontend state)
- Both servers can reload independently without affecting each other

### Proxy Mechanism

In frontend mode, API requests are automatically proxied to the backend:

1. Frontend server receives an API request (e.g., `/user/login`)
2. Request is forwarded to backend server at `http://127.0.0.1:{port+1}`
3. Backend processes the request and returns a response
4. Frontend server forwards the response back to the client

**Proxied Endpoints:**
- Authentication: `/user/register`, `/user/login`
- API discovery: `/functions`, `/walkers`
- Function execution: `/function/<name>`
- Walker execution: `/walker/<name>`
- Protected routes: `/protected`

This allows developers to access all backend APIs through the frontend server URL, simplifying development and avoiding CORS issues.

### Process Lifecycle

**Startup Sequence:**
1. Parse command-line arguments (filename, port, session)
2. Start frontend server process
3. Wait 0.5 seconds for initialization
4. Start backend server process
5. Begin file watching loop

**Shutdown Sequence:**
1. Detect shutdown signal (Ctrl+C or exception)
2. Set shutdown flag to stop file watcher
3. Terminate both server processes
4. Wait for graceful shutdown (2-second timeout)
5. Force kill if processes don't terminate
6. Clean up resources and exit

**Auto-Recovery:**
- If a server process crashes unexpectedly, it's automatically restarted
- Process health is checked on each file watch iteration
- Backend runs quietly (suppressed output) to reduce console noise

## Benefits

### Developer Experience
- **Fast Iteration**: Only affected server restarts, reducing downtime
- **Clear Separation**: Frontend and backend concerns are explicitly separated
- **Auto-Configuration**: No manual proxy setup or CORS configuration needed
- **Instant Feedback**: File changes trigger immediate reloads

### Performance
- **Parallel Development**: Frontend and backend can be developed independently
- **Efficient Reloads**: Changing CSS doesn't restart your API server
- **Resource Optimization**: Each server loads only what it needs

### Scalability
- **Production-Ready Pattern**: Mirrors production deployment with separate frontend/backend
- **Easy Transition**: Same code structure works in dev and production
- **Flexible Deployment**: Can deploy frontend and backend independently

## Usage Examples

### Basic Usage
```bash
jac dev myapp.jac
```
Starts frontend on port 8000, backend on port 8001.

### Custom Port
```bash
jac dev myapp.jac --port 3000
```
Starts frontend on port 3000, backend on port 3001.

### With Session
```bash
jac dev myapp.jac --session myapp.session
```
Uses persistent session storage for both servers.

## Comparison with `jac serve`

| Feature | `jac serve` | `jac dev` |
|---------|-------------|-----------|
| Servers | Single unified server | Two separate servers |
| Hot Reload | No | Yes, with selective reloading |
| Port Usage | Single port | Two consecutive ports |
| File Watching | No | Yes |
| Best For | Production, testing | Active development |
| Mode Support | All, frontend, backend | Always splits frontend/backend |

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                     jac dev                              │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │           File Watcher (watchfiles)            │    │
│  │                                                 │    │
│  │  Monitors: .jac, .cl.jac, .py, .html, .css,   │    │
│  │           .js, images, fonts, etc.             │    │
│  └─────────────┬────────────────────┬─────────────┘    │
│                │                    │                   │
│    Frontend    │                    │    Backend        │
│    Change      │                    │    Change         │
│                ▼                    ▼                   │
│  ┌──────────────────┐    ┌──────────────────┐          │
│  │  Frontend Server │    │  Backend Server  │          │
│  │   (Port 8000)    │    │   (Port 8001)    │          │
│  │                  │    │                  │          │
│  │ • Static files   │    │ • API endpoints  │          │
│  │ • .cl.jac files  │    │ • Functions      │          │
│  │ • Pages/routing  │    │ • Walkers        │          │
│  │ • Proxy to       │◄───┤ • Auth           │          │
│  │   backend        │───►│ • Business logic │          │
│  └──────────────────┘    └──────────────────┘          │
│           │                       │                     │
│           └───────────┬───────────┘                     │
│                       │                                 │
└───────────────────────┼─────────────────────────────────┘
                        │
                        ▼
                   Developer
              (Browser/API Client)
```

## Conclusion

The `jac dev` command provides an intelligent, production-like development environment that separates concerns, optimizes reload times, and simplifies the development workflow. By automatically managing two servers and selectively reloading based on file changes, it enables rapid iteration while maintaining a clean architecture that mirrors production deployments.
