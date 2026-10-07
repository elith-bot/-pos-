import sys
import json
import traceback
from core_system import core
import actions  # Import actions to register them
from app import create_app

app = create_app()

def run_mcp_server():
    """
    A lightweight, standard Model Context Protocol (MCP) stdio server.
    This reads JSON-RPC from stdin and writes responses to stdout.
    """
    while True:
        line = sys.stdin.readline()
        if not line:
            break
            
        try:
            req = json.loads(line)
            
            # MCP Initialization
            if req.get('method') == 'initialize':
                response = {
                    "jsonrpc": "2.0",
                    "id": req.get('id'),
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {
                            "tools": {}
                        },
                        "serverInfo": {
                            "name": "Casher-MCP-Core",
                            "version": "1.0.0"
                        }
                    }
                }
                print(json.dumps(response))
                sys.stdout.flush()
                continue
                
            # List Tools
            elif req.get('method') == 'tools/list':
                tools = []
                metadata = core.get_all_actions_metadata()
                
                for name, info in metadata.items():
                    properties = {}
                    required = []
                    
                    for p_name, p_info in info["parameters"].items():
                        properties[p_name] = {"type": "string" if p_info["type"] == "str" else "number" if p_info["type"] in ["int", "float"] else p_info["type"]}
                        if p_info["required"]:
                            required.append(p_name)
                            
                    tools.append({
                        "name": name,
                        "description": info["description"],
                        "inputSchema": {
                            "type": "object",
                            "properties": properties,
                            "required": required
                        }
                    })
                    
                response = {
                    "jsonrpc": "2.0",
                    "id": req.get('id'),
                    "result": {
                        "tools": tools
                    }
                }
                print(json.dumps(response))
                sys.stdout.flush()
                continue

            # Call Tool
            elif req.get('method') == 'tools/call':
                params = req.get('params', {})
                tool_name = params.get('name')
                tool_args = params.get('arguments', {})
                
                try:
                    with app.app_context():
                        result = core.execute(tool_name, tool_args)
                    
                    response = {
                        "jsonrpc": "2.0",
                        "id": req.get('id'),
                        "result": {
                            "content": [
                                {
                                    "type": "text",
                                    "text": json.dumps(result, ensure_ascii=False)
                                }
                            ]
                        }
                    }
                except Exception as e:
                    response = {
                        "jsonrpc": "2.0",
                        "id": req.get('id'),
                        "result": {
                            "content": [{"type": "text", "text": str(e)}],
                            "isError": True
                        }
                    }
                
                print(json.dumps(response))
                sys.stdout.flush()
                continue
                
        except Exception as e:
            # Fatal error
            pass

if __name__ == "__main__":
    run_mcp_server()
