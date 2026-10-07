import inspect
from functools import wraps

class CoreRegistry:
    def __init__(self):
        self.actions = {}

    def action(self, name, description):
        """
        Decorator to register a function as a core system action.
        This makes it accessible via API and MCP automatically.
        """
        def decorator(func):
            sig = inspect.signature(func)
            params = {}
            for param_name, param in sig.parameters.items():
                if param_name == 'self':
                    continue
                
                # Get type name if possible, default to any
                param_type = "string"
                if hasattr(param.annotation, '__name__'):
                    param_type = param.annotation.__name__
                elif type(param.annotation) == type:
                    param_type = param.annotation.__name__
                
                params[param_name] = {
                    "type": param_type,
                    "required": param.default == inspect.Parameter.empty
                }

            self.actions[name] = {
                "func": func,
                "description": description,
                "parameters": params
            }

            @wraps(func)
            def wrapper(*args, **kwargs):
                return func(*args, **kwargs)
            return wrapper
        return decorator

    def execute(self, name, kwargs):
        """Execute a registered action with the given kwargs."""
        if name not in self.actions:
            raise ValueError(f"Action '{name}' not found in core registry.")
        return self.actions[name]["func"](**kwargs)

    def get_all_actions_metadata(self):
        """Returns metadata for all actions, useful for MCP server."""
        return {
            name: {
                "description": info["description"], 
                "parameters": info["parameters"]
            } 
            for name, info in self.actions.items()
        }

# Global registry instance
core = CoreRegistry()
