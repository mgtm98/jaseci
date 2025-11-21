# JServer: Abstract Server Framework for JAC Scale

## Overview

JAC Scale provides a flexible, abstract server framework through the `jserver` module. This framework defines a standardized way to create and manage API endpoints across different server implementations (FastAPI, Flask, native Python HTTP server, etc.) while maintaining consistency and type safety.

## Core Components

### 1. JEndPoint - The Endpoint Definition

`JEndPoint` is a dataclass that represents a single API endpoint configuration. It encapsulates all the information needed to define an API route:

```python
@dataclass
class JEndPoint:
    method: HTTPMethod                                    # HTTP method (GET, POST, etc.)
    path: str                                            # URL path pattern
    callback: Callable[..., Any]                        # Handler function
    parameters: Optional[List[Dict[str, Any]]] = None    # Parameter definitions
    response_model: Optional[Type[BaseModel]] = None     # Response validation model
    tags: Optional[List[str]] = None                     # API documentation tags
    summary: Optional[str] = None                        # Short description
    description: Optional[str] = None                    # Detailed description
```

#### Example JEndPoint Definition

```python
# Simple GET endpoint
get_users_endpoint = JEndPoint(
    method=HTTPMethod.GET,
    path="/users",
    callback=get_users_handler,
    summary="Get all users",
    description="Retrieve a list of all users in the system",
    tags=["users"]
)

# POST endpoint with parameters
create_user_endpoint = JEndPoint(
    method=HTTPMethod.POST,
    path="/users",
    callback=create_user_handler,
    parameters=[
        {
            "name": "name",
            "in": ParameterType.BODY,
            "type": "str",
            "required": True,
            "description": "User's full name"
        },
        {
            "name": "email",
            "in": ParameterType.BODY,
            "type": "str",
            "required": True,
            "description": "User's email address"
        }
    ],
    summary="Create new user",
    tags=["users"]
)
```

### 2. JServer - The Abstract Server Class

`JServer` is an abstract base class that defines the interface for server implementations. It uses Python's Generic typing to allow concrete implementations to specify their server type.

```python
class JServer(ABC, Generic[T]):
    def __init__(self, end_points: List[JEndPoint]) -> None
    def get_endpoints(self) -> List[JEndPoint]
    def add_endpoint(self, endpoint: JEndPoint) -> None
    def execute(self) -> None

    # Abstract methods that must be implemented
    @abstractmethod
    def _get(self, endpoint: JEndPoint) -> "JServer[T]"
    @abstractmethod
    def _post(self, endpoint: JEndPoint) -> "JServer[T]"
    @abstractmethod
    def _put(self, endpoint: JEndPoint) -> "JServer[T]"
    @abstractmethod
    def _patch(self, endpoint: JEndPoint) -> "JServer[T]"
    @abstractmethod
    def _delete(self, endpoint: JEndPoint) -> "JServer[T]"
    @abstractmethod
    def create_server(self) -> T
```

## How It Works

### 1. Define Endpoints
Create `JEndPoint` instances that describe your API endpoints:

```python
endpoints = [
    JEndPoint(HTTPMethod.GET, "/health", health_check),
    JEndPoint(HTTPMethod.GET, "/users", get_users),
    JEndPoint(HTTPMethod.POST, "/users", create_user, parameters=[...]),
    JEndPoint(HTTPMethod.GET, "/users/{user_id}", get_user, parameters=[...])
]
```

### 2. Create Server Implementation
Instantiate a concrete server implementation with your endpoints:

```python
# Or using native Python HTTP server implementation
server = JNativeHttpServer(endpoints)
```

### 3. Execute and Deploy
Execute the endpoints to create the actual server routes:

```python
# Create the configured server
app = server.create_server()
server.serve_forever()  # For native HTTP server
```

## Implementation Examples

### Native Python HTTP Server Implementation

```python
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import json
import re
from typing import Dict, Any, Optional

class JNativeHttpServer(JServer[HTTPServer]):
    def __init__(self, endpoints: Optional[List[JEndPoint]] = None) -> None:
        super().__init__(endpoints or [])
        self.routes: Dict[str, Dict[str, JEndPoint]] = {}
        self.server: Optional[HTTPServer] = None

    def _register_route(self, method: HTTPMethod, endpoint: JEndPoint) -> None:
        """Register a route with the native HTTP server."""
        if endpoint.path not in self.routes:
            self.routes[endpoint.path] = {}
        self.routes[endpoint.path][method.value] = endpoint

    def _get(self, endpoint: JEndPoint) -> "JNativeHttpServer":
        self._register_route(HTTPMethod.GET, endpoint)
        return self

    def _post(self, endpoint: JEndPoint) -> "JNativeHttpServer":
        self._register_route(HTTPMethod.POST, endpoint)
        return self

    def _put(self, endpoint: JEndPoint) -> "JNativeHttpServer":
        self._register_route(HTTPMethod.PUT, endpoint)
        return self

    def _patch(self, endpoint: JEndPoint) -> "JNativeHttpServer":
        self._register_route(HTTPMethod.PATCH, endpoint)
        return self

    def _delete(self, endpoint: JEndPoint) -> "JNativeHttpServer":
        self._register_route(HTTPMethod.DELETE, endpoint)
        return self

    def create_server(self, host: str = "localhost", port: int = 8000) -> HTTPServer:
        """Create and configure the native HTTP server."""
        self.execute()

        class RequestHandler(BaseHTTPRequestHandler):
            def __init__(self, routes, *args, **kwargs):
                self.routes = routes
                super().__init__(*args, **kwargs)

            def do_GET(self):
                self._handle_request('GET')

            def do_POST(self):
                self._handle_request('POST')

            def do_PUT(self):
                self._handle_request('PUT')

            def do_PATCH(self):
                self._handle_request('PATCH')

            def do_DELETE(self):
                self._handle_request('DELETE')

            def _handle_request(self, method: str):
                parsed_url = urlparse(self.path)
                path = parsed_url.path
                query_params = parse_qs(parsed_url.query)

                # Find matching endpoint
                endpoint = self._find_endpoint(path, method)
                if not endpoint:
                    self.send_error(404, "Not Found")
                    return

                try:
                    # Extract parameters
                    kwargs = {}

                    # Handle path parameters
                    path_params = self._extract_path_params(path, endpoint.path)
                    kwargs.update(path_params)

                    # Handle query parameters
                    for key, values in query_params.items():
                        kwargs[key] = values[0] if len(values) == 1 else values

                    # Handle body parameters for POST/PUT/PATCH
                    if method in ['POST', 'PUT', 'PATCH']:
                        content_length = int(self.headers.get('Content-Length', 0))
                        if content_length > 0:
                            body = self.rfile.read(content_length)
                            try:
                                body_data = json.loads(body.decode('utf-8'))
                                kwargs.update(body_data)
                            except json.JSONDecodeError:
                                self.send_error(400, "Invalid JSON")
                                return

                    # Call the endpoint callback
                    result = endpoint.callback(**kwargs)

                    # Send response
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()

                    response_data = json.dumps(result if result is not None else {})
                    self.wfile.write(response_data.encode('utf-8'))

                except Exception as e:
                    self.send_error(500, str(e))

            def _find_endpoint(self, path: str, method: str) -> Optional[JEndPoint]:
                # First try exact match
                if path in self.routes and method in self.routes[path]:
                    return self.routes[path][method]

                # Try pattern matching for parameterized paths
                for route_path, methods in self.routes.items():
                    if method in methods and self._path_matches(path, route_path):
                        return methods[method]

                return None

            def _path_matches(self, request_path: str, route_path: str) -> bool:
                # Convert route path with {param} to regex pattern
                pattern = re.sub(r'\{[^}]+\}', r'([^/]+)', route_path)
                pattern = f"^{pattern}$"
                return bool(re.match(pattern, request_path))

            def _extract_path_params(self, request_path: str, route_path: str) -> Dict[str, Any]:
                params = {}

                # Extract parameter names from route path
                param_names = re.findall(r'\{([^}]+)\}', route_path)

                # Convert route path to regex and extract values
                pattern = re.sub(r'\{[^}]+\}', r'([^/]+)', route_path)
                pattern = f"^{pattern}$"
                match = re.match(pattern, request_path)

                if match and param_names:
                    for name, value in zip(param_names, match.groups()):
                        params[name] = value

                return params

        # Create handler class with routes
        handler = lambda *args, **kwargs: RequestHandler(self.routes, *args, **kwargs)

        self.server = HTTPServer((host, port), handler)
        return self.server

    def serve_forever(self, host: str = "localhost", port: int = 8000) -> None:
        """Start the server and serve forever."""
        server = self.create_server(host, port)
        print(f"Starting native HTTP server on http://{host}:{port}")
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server...")
            server.shutdown()

# Example usage
def get_users():
    return [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}]

def get_user(user_id: str):
    return {"id": int(user_id), "name": f"User {user_id}"}

def create_user(name: str, email: str):
    return {"message": "User created", "user": {"name": name, "email": email}}

endpoints = [
    JEndPoint(HTTPMethod.GET, "/users", get_users),
    JEndPoint(HTTPMethod.GET, "/users/{user_id}", get_user),
    JEndPoint(HTTPMethod.POST, "/users", create_user)
]

# Create and start native HTTP server
server = JNativeHttpServer(endpoints)
server.serve_forever(host="0.0.0.0", port=8000)
```

## Parameter Configuration

Parameters are defined as dictionaries with the following structure:

```python
parameter = {
    "name": "parameter_name",           # Parameter name
    "in": ParameterType.QUERY,          # Where the parameter is located
    "type": "str",                      # Parameter type (str, int, float, bool)
    "required": True,                   # Whether parameter is required
    "description": "Parameter desc",     # Documentation description
    "default": None                     # Default value (for optional parameters)
}
```

### Parameter Types by Location

- **Query Parameters**: `?name=value&limit=10`
- **Path Parameters**: `/users/{user_id}/posts/{post_id}`
- **Body Parameters**: JSON payload in request body
- **Header Parameters**: HTTP headers

## Future Extensions

The framework is designed to support future extensions:

- **Middleware Support**: Add middleware configuration to JEndPoint
- **Authentication**: Built-in authentication parameter types
- **Rate Limiting**: Endpoint-level rate limiting configuration
- **Caching**: Response caching configuration
- **Validation**: Advanced parameter validation rules

This abstraction layer makes JAC Scale's server framework highly flexible while maintaining consistency across different server implementations.