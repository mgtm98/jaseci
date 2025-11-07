/**
 * jac-client
 * Utility functions for Jac Client runtime
 */

// Helper functions for localStorage
function __getLocalStorage(key) {
  const storage = globalThis.localStorage;
  return storage ? storage.getItem(key) : "";
}

function __setLocalStorage(key, value) {
  const storage = globalThis.localStorage;
  if (storage) {
    storage.setItem(key, value);
  }
}

function __removeLocalStorage(key) {
  const storage = globalThis.localStorage;
  if (storage) {
    storage.removeItem(key);
  }
}

/**
 * Spawn a walker on the backend
 * @param {string} walker - Name of the walker to execute
 * @param {object} fields - Dictionary of parameters to pass to the walker
 * @param {string} [nd] - Optional node ID (defaults to "root")
 * @returns {Promise<any>} The result from the walker execution
 */
async function jacSpawn(walker, fields = {}, nd) {
  const token = __getLocalStorage("jac_token");
  const response = await fetch(`/walker/${walker}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": token ? `Bearer ${token}` : ""
    },
    body: JSON.stringify({
      nd: nd ? nd : "root",
      ...fields
    })
  });

  if (!response.ok) {
    const error_text = await response.text();
    throw new Error(`Walker ${walker} failed: ${error_text}`);
  }

  return JSON.parse(await response.text());
}

/**
 * Call a server-side function from the client
 * @param {string} function_name - Name of the function to call
 * @param {object} args - Dictionary of arguments to pass to the function
 * @returns {Promise<any>} The result from the function call
 */
async function jacCallFunction(function_name, args = {}) {
  const token = __getLocalStorage("jac_token");
  const response = await fetch(`/function/${function_name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": token ? `Bearer ${token}` : ""
    },
    body: JSON.stringify({ args })
  });

  if (!response.ok) {
    const error_text = await response.text();
    throw new Error(`Function ${function_name} failed: ${error_text}`);
  }

  const data = JSON.parse(await response.text());
  return data["result"];
}

/**
 * Sign up a new user
 * @param {string} username - Username for the new account
 * @param {string} password - Password for the new account
 * @returns {Promise<{success: boolean, token?: string, username?: string, error?: string}>}
 */
async function jacSignup(username, password) {
  const response = await fetch("/user/create", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ username, password })
  });

  if (response.ok) {
    const data = JSON.parse(await response.text());
    const token = data["token"];
    if (token) {
      __setLocalStorage("jac_token", token);
      return { success: true, token, username };
    }
    return { success: false, error: "No token received" };
  } else {
    const error_text = await response.text();
    try {
      const error_data = JSON.parse(error_text);
      return {
        success: false,
        error: error_data["error"] !== null ? error_data["error"] : "Signup failed"
      };
    } catch {
      return { success: false, error: error_text };
    }
  }
}

/**
 * Log in an existing user
 * @param {string} username - Username
 * @param {string} password - Password
 * @returns {Promise<boolean>} True if login successful, false otherwise
 */
async function jacLogin(username, password) {
  const response = await fetch("/user/login", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ username, password })
  });

  if (response.ok) {
    const data = JSON.parse(await response.text());
    const token = data["token"];
    if (token) {
      __setLocalStorage("jac_token", token);
      return true;
    }
  }
  return false;
}

/**
 * Log out the current user (removes token from localStorage)
 */
function jacLogout() {
  __removeLocalStorage("jac_token");
}

/**
 * Check if a user is currently logged in
 * @returns {boolean} True if a token exists, false otherwise
 */
function jacIsLoggedIn() {
  const token = __getLocalStorage("jac_token");
  return token !== null && token !== "";
}

// Export all functions
module.exports = {
  jacSpawn,
  jacCallFunction,
  jacSignup,
  jacLogin,
  jacLogout,
  jacIsLoggedIn
};

