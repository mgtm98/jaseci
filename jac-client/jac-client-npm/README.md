# jac-client

Utility functions for Jac Client runtime - spawn walkers, call functions, and handle authentication.

## Installation

```bash
npm install jac-client
```

## Usage

### Import the functions

```javascript
const {
  jacSpawn,
  jacCallFunction,
  jacSignup,
  jacLogin,
  jacLogout,
  jacIsLoggedIn
} = require('jac-client');
```

Or with ES modules:

```javascript
import {
  jacSpawn,
  jacCallFunction,
  jacSignup,
  jacLogin,
  jacLogout,
  jacIsLoggedIn
} from 'jac-client';
```

## API Reference

### `jacSpawn(walker, fields, nd?)`

Spawn a walker on the backend.

**Parameters:**
- `walker` (string): Name of the walker to execute
- `fields` (object, optional): Dictionary of parameters to pass to the walker
- `nd` (string, optional): Node ID (defaults to "root")

**Returns:** `Promise<any>` - The result from the walker execution

**Example:**
```javascript
// Create a new todo
const newTodo = await jacSpawn("create_todo", { text: "New todo" });

// Toggle todo status
const toggledTodo = await jacSpawn("toggle_todo", {}, todoId);

// Read all todos
const todos = await jacSpawn("read_todos");
```

### `jacCallFunction(function_name, args?)`

Call a server-side function from the client.

**Parameters:**
- `function_name` (string): Name of the function to call
- `args` (object, optional): Dictionary of arguments to pass to the function

**Returns:** `Promise<any>` - The result from the function call

**Example:**
```javascript
const result = await jacCallFunction("calculate_total", { items: [1, 2, 3] });
```

### `jacSignup(username, password)`

Sign up a new user.

**Parameters:**
- `username` (string): Username for the new account
- `password` (string): Password for the new account

**Returns:** `Promise<{success: boolean, token?: string, username?: string, error?: string}>`

**Example:**
```javascript
const result = await jacSignup("john_doe", "password123");
if (result.success) {
  console.log("Signed up successfully!", result.token);
} else {
  console.error("Signup failed:", result.error);
}
```

### `jacLogin(username, password)`

Log in an existing user.

**Parameters:**
- `username` (string): Username
- `password` (string): Password

**Returns:** `Promise<boolean>` - True if login successful, false otherwise

**Example:**
```javascript
const success = await jacLogin("john_doe", "password123");
if (success) {
  console.log("Logged in successfully!");
} else {
  console.error("Login failed");
}
```

### `jacLogout()`

Log out the current user (removes token from localStorage).

**Example:**
```javascript
jacLogout();
console.log("Logged out");
```

### `jacIsLoggedIn()`

Check if a user is currently logged in.

**Returns:** `boolean` - True if a token exists, false otherwise

**Example:**
```javascript
if (jacIsLoggedIn()) {
  console.log("User is logged in");
} else {
  console.log("User is not logged in");
}
```

## Authentication Flow

The authentication functions automatically manage the JWT token in localStorage:

1. **Signup/Login**: Automatically stores the token in localStorage as `jac_token`
2. **Logout**: Removes the token from localStorage
3. **API Calls**: `jacSpawn` and `jacCallFunction` automatically include the token in the Authorization header if present

## Requirements

- Node.js >= 14.0.0
- Browser environment with `fetch` API and `localStorage` support

## License

MIT License

