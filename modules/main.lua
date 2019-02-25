local cjson = require('cjson')

local access_control = require('access_control')
local api_call = require('api_call')
local cors = require('cors')
local health_check = require('health_check')
local log = require('log')
local parse_and_validate_request = require('parse_and_validate_request')
local rate_limiting = require('rate_limiting')
local is_response_error = require('shared').is_response_error

local function global_headers(ssl_enabled, response)
  response.headers['Content-Security-Policy'] = "default-src 'none'"
  response.headers['Content-Type'] = 'application/json; charset=utf-8'
  response.headers['Referrer-Policy'] = 'same-origin'
  response.headers['X-Content-Type-Options'] = 'nosniff'
  response.headers['X-Frame-Options'] = 'SAMEORIGIN'
  response.headers['X-XSS-Protection'] = '1; mode=block'

  if ssl_enabled then
    response.headers['Strict-Transport-Security'] = 'max-age=63072000;'
  end
end

local function init_request_object()
  return {
    body = nil,
    client_ip = ngx.var.remote_addr,
    is_health_check = false,
    is_cors_preflight = false,
    is_api_call = false,
    json_rpc = nil,
  }
end

local function init_response_object()
  return {
    headers = {},
    status = nil,
    json_rpc = {
      id = 'null',
      jsonrpc = '2.0',
      error = nil,
      result = nil,
    },
  }
end

local function send_response(response)
  ngx.status = response.status or 520 -- Unknown error

  local response_json = cjson.encode(response.json_rpc)

  ngx.header['Content-Length'] = string.len(response_json)

  for header, value in pairs(response.headers) do
    ngx.header[header] = value
  end

  ngx.print(response_json)
  ngx.exit(response.status)
end

local function init(config)
  access_control.init(config)
  rate_limiting.init(config)
end

local function go(config)
  local request = init_request_object()
  local response = init_response_object()

  global_headers(config.ssl_enabled, response)

  access_control.check_access(request, response)

  if not is_response_error(response) then
    pcall(parse_and_validate_request, request, response)

    cors(config, request, response)

    if not is_response_error(response) then
      if request.is_health_check then
        health_check(config, response)

      elseif request.is_api_call then
        rate_limiting.enforce_limits(request, response)

        if not is_response_error(response) then
          api_call(request, response)
        end
      end
    end
  end

  log(request, response)

  send_response(response)
end

return {
  init = init,
  go = go,
}