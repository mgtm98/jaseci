/**
 * jac-client
 * TypeScript definitions for Jac Client runtime utilities
 */

/**
 * Spawn a walker on the backend
 * @param walker - Name of the walker to execute
 * @param fields - Dictionary of parameters to pass to the walker
 * @param nd - Optional node ID (defaults to "root")
 * @returns The result from the walker execution
 */
declare function jacSpawn(
  walker: string,
  fields?: Record<string, any>,
  nd?: string
): Promise<any>;

/**
 * Call a server-side function from the client
 * @param function_name - Name of the function to call
 * @param args - Dictionary of arguments to pass to the function
 * @returns The result from the function call
 */
declare function jacCallFunction(
  function_name: string,
  args?: Record<string, any>
): Promise<any>;

/**
 * Sign up a new user
 * @param username - Username for the new account
 * @param password - Password for the new account
 * @returns Object with success status, token, username, or error message
 */
declare function jacSignup(
  username: string,
  password: string
): Promise<{
  success: boolean;
  token?: string;
  username?: string;
  error?: string;
}>;

/**
 * Log in an existing user
 * @param username - Username
 * @param password - Password
 * @returns True if login successful, false otherwise
 */
declare function jacLogin(
  username: string,
  password: string
): Promise<boolean>;

/**
 * Log out the current user (removes token from localStorage)
 */
declare function jacLogout(): void;

/**
 * Check if a user is currently logged in
 * @returns True if a token exists, false otherwise
 */
declare function jacIsLoggedIn(): boolean;

export {
  jacSpawn,
  jacCallFunction,
  jacSignup,
  jacLogin,
  jacLogout,
  jacIsLoggedIn
};

