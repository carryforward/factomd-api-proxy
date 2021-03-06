# Factomd API Proxy

A lightweight proxy, custom-built to enhance the factomd API port.

## Features:

* **CORS support:** Includes wildcard support and PERL regular expression syntax for specifying 
allowed origins.

* **SSL support:** High-grade SSL configuration that can deliver an A+ SSL Labs rating,
given a strong cert/key pair.

* **Rate limiting:** Writes-per-second and writes-per-block rate limiting. Includes burst
throttling, which spreads groups of writes over a longer period.

* **Health check support:** The `GET /` endpoint performs tests on the underlying factomd 
instance and returns a detailed diagnostic payload. This allows the API to work correctly 
with cloud provider load balancers, and streamlines the development of monitoring
infrastructure.

* **Access Control Whitelist:** An optional whitelist of IP addresses and/or networks can be
provided to restrict client connections.

* **Detailed logging:** API method names are logged, along with the usual information.

* **Strict protocol operation:** Only a very narrow range of HTTP verbs and URIs are
passed through to factomd.

* **Dynamic reconfiguration:** Edits to the YAML configuration files will cause an automatic
reload of the Nginx configuration, eliminating the need to restart the container in most cases.

* **Kubernetes ready:** The ability to split configuration into multiple files dovetails
perfectly with Kubernetes configuration patterns. Painlessly store most of the configuration 
in one or more ConfigMaps, while storing sensitive data such as the SSL private key in a 
Secret. No impedance mismatch!

## Supported Tags and Dockerfile Links

* [`latest` (*Dockerfile*)](https://github.com/BedrockSolutions/factomd-api-proxy/blob/master/Dockerfile)
  
* [`0.5.2` (*Dockerfile*)](https://github.com/BedrockSolutions/factomd-api-proxy/blob/0.5.2/Dockerfile)

## In-depth Feature Discussion

### Rate Limiting

The rate limiting subsystem can limit writes-per-second and writes-per-block. Default configuration
enables both modes with sensible defaults.

#### Writes-per-second limiting

WPS limiting helps control bursts of write activity on the network.
Two settings control WPS limiting: `rateLimiting.maxWritesPerSecond` and 
`rateLimiting.maxBurstWritesPerSecond`. Together, these two settings create three rate 
limiting regions:

```
0 |--- A ---| maxWritesPerSecond |--- B ---| maxBurstWritesPerSecond |--- C --->
```
In region "A" the WPS is below the `maxWritesPerSecond` value. All write requests sent
to the proxy will be immediately sent to the upstream factomd.

In region "B" the WPS is between the `maxWritesPerSecond` and `maxBurstWritesPerSecond`
values. Write requests will be sent to the upstream factomd at the `maxWritesPerSecond`
rate. Requests will be delayed by the proxy by some amount so that the writes are
spread over a longer time period.

In region "C" the WPS is greater than the `maxBurstWritesPerSecond` value. Write requests 
will be sent to the upstream factomd at the `maxWritesPerSecond` rate. Some requests
will be delayed by the proxy as in region "B". Other requests will be immediately
rejected with an HTTP 429 error.

#### Writes-per-block limiting

WPB limiting helps keep the number of writes in a given block within more reasonable
limits.
Two settings control WPB limiting: `rateLimiting.blockDurationInSeconds` and
`rateLimiting.maxWritesPerBlock`. 

> In WPB limiting, the concept of a block is simply a duration. It does not actually 
line up with the beginning and end of a block on the blockchain.

WPB limiting sets the maximum number of writes allowed over a set interval. If the 
write quota is exceeded, the request will be rejected with an HTTP 429 error.

## Configuration

All configuration is done via one or more YAML configuration files mounted under the 
`/home/app/values` directory. Configuration can be contained in a single file, multiple 
files, and multiple directories. The `/home/app/values` directory will be recursively 
traversed, and all files found with the `.yaml` suffix will be merged to create the final 
configuration.

Steps to configure the proxy:

1. Create a directory to hold the configuration.
    * You must create a directory. Do not attempt to mount just a file into the container!
2. Place one or more YAML configuration files in the directory. 
    * All configuration file names must have the `.yaml` extension.
    * Only `.yaml` files will be read for configuration. All other files are ignored.
    * Subdirectories can be created within the configuration directory if needed. 
3. Mount the directory to the container's `/home/app/values` directory during `docker run`.
    * The source path must be an absolute path.
    * The destination path must be `/home/app/values`
    * Example `docker` option: `-v /abs/path/to/config/dir:/home/app/values`

**To reconfigure the proxy, simply edit the configuration file(s) while the 
container is running.**
  * The Nginx process will automatically reload the changed config.
  * Configuration errors will be reported in `docker logs`

### Example

In this example, configuration has been split between two files. The `common.yaml` file holds
configuration common to all proxy instances being deployed. The `local.yaml` file holds 
configuration specific to a given proxy instance. To bootstrap a given proxy instance, both
files are needed.

First, create a configuration directory:
```bash
mkdir proxy_config
```
Second, create a YAML file in the previous directory to hold common configuration:
```yaml
# ./proxy_config/common.yaml
---
accessControlWhitelist:
- 1.2.3.0/24
- 10.20.0.0/16

corsAllowOrigin: "^https://my\.domain\.com$"

factomdUrl: http://localhost:8080

ssl:
  trustedCertificate: |-
    -----BEGIN CERTIFICATE-----
    eTAeFw0xNjAyMjIxODI0MDBaFw0yMTAyMjIwMDI0MDBaMIGPMQswCQYDVQQGEwJV
    UzETMBEGA1UECBMKQ2FsaWZvcm5pYTEWMBQGA1UEBxMNU2FuIEZyYW5jaXNjbzEZ
    MBcGA1UEChMQQ2xvdWRGbGFyZSwgSW5jLjE4MDYGA1UECxMvQ2xvdWRGbGFyZSBP
    tBoOOKcwHwYDVR0jBBgwFoAUhTBdOypw1O3VkmcH/es5tBoOOKcwCgYIKoZIzj0E
    mcifak4CQsr+DH4pn5SJD7JxtCG3YGswW8QZsw==
    -----END CERTIFICATE-----
...
```
Third, create a YAML file to hold deployment-specific config:
```yaml
# ./proxy_config/local.yaml
---
ssl:
  certificate: |-
    -----BEGIN CERTIFICATE-----
    eTAeFw0xNjAyMjIxODI0MDBaFw0yMTAyMjIwMDI0MDBaMIGPMQswCQYDVQQGEwJV
    UzETMBEGA1UECBMKQ2FsaWZvcm5pYTEWMBQGA1UEBxMNU2FuIEZyYW5jaXNjbzEZ
    MBcGA1UEChMQQ2xvdWRGbGFyZSwgSW5jLjE4MDYGA1UECxMvQ2xvdWRGbGFyZSBP
    tBoOOKcwHwYDVR0jBBgwFoAUhTBdOypw1O3VkmcH/es5tBoOOKcwCgYIKoZIzj0E
    mcifak4CQsr+DH4pn5SJD7JxtCG3YGswW8QZsw==
    -----END CERTIFICATE-----
    
  certificateKey: |-
    -----BEGIN PRIVATE KEY-----
    eTAeFw0xNjAyMjIxODI0MDBaFw0yMTAyMjIwMDI0MDBaMIGPMQswCQYDVQQGEwJV
    UzETMBEGA1UECBMKQ2FsaWZvcm5pYTEWMBQGA1UEBxMNU2FuIEZyYW5jaXNjbzEZ
    MBcGA1UEChMQQ2xvdWRGbGFyZSwgSW5jLjE4MDYGA1UECxMvQ2xvdWRGbGFyZSBP
    tBoOOKcwHwYDVR0jBBgwFoAUhTBdOypw1O3VkmcH/es5tBoOOKcwCgYIKoZIzj0E
    mcifak4CQsr+DH4pn5SJD7JxtCG3YGswW8QZsw==
    -----END PRIVATE KEY-----
...
```
Forth, start the container:
```bash
docker run -d -p 443:8443 --name proxy \
  -v /path/to/proxy_config:/home/app/values \
  bedrocksolutions/factomd-api-proxy:0.5.2
```

## Primary options

* **`accessControlWhitelist`:** An array of allowed IP addresses and IP networks in CIDR format. If
omitted, all addresses are allowed to connect. Example:

```yaml
accessControlWhitelist:
- 10.0.0.0/8
- 192.168.0.0/16
- 1.2.3.4
- 5.6.7.8/32
```

* **`corsAllowOrigin`:** Configures CORS. Three modes of operation are supported:

  * `""`: Disables CORS. This is the default
  
  * `"*"`: Enables CORS in wildcard mode. This will allow all browsers to use
  the API.
  
  * `"<PERL Regular Expression>"`: Enables CORS only for origins that match the regular expression.
  Some examples:
  
    * `^http://www\.foo\.com$`: Exact match of one domain.
    
    * `^https?://.*foo\.com$`: Matches all origins ending in `foo.com`. Both http
    and https URLs match.
    
    * `^http://(foo|bar)\.com$`: Exact match for either `http://foo.com`
    or `http://bar.com`.
  
  > Note: In a regex, special characters, such as the period, need to be escaped with a backslash.
  
* **`factomdUrl`:** URL of the upstream factomd instance. Defaults 
to `http://courtesy-node.factom.com`.

* **`listenPort`:** The port the proxy will listen on. Defaults to `8080` for non-SSL operation,
and `8443` when SSL is enabled.

* **`rateLimiting.blockDurationInSeconds`:** The duration of a rate-limiting block.
Defaults to 600.

* **`rateLimiting.maxBurstWritesPerSecond`:** The maximum writes-per-second that will be buffered
before requests are rejected. Defaults to 10.

* **`rateLimiting.maxWritesPerBlock`:** The maximum number of writes that can be sent during a 
rate-limiting block. A block is simply a period of time, and does not actually correspond to 
a Factom block. Defaults to 600.

* **`rateLimiting.maxWritesPerSecond`:** The maximum writes-per-second that will be sent to the
upstream factomd instance. Defaults to 2.

* **`ssl.certificate`:** Certificate chain in PEM format. If this plus `ssl.certificateKey` are 
present, SSL will be enabled. Although it is possible specify just the server certificate here, 
normally the entire chain of certificates should be specified, starting with the server certificate, 
proceeding through zero or more intermediary certificates, and ending with the root certificate.
All of these certificates will be sent to the client.

* **`ssl.certificateKey`:** Private key in PEM format. If this plus `ssl.certificate` are present,
SSL will be enabled.
 
* **`ssl.trustedCertificate`:**  Certificate chain of intermediate and root certificates,
in PEM format. Used to verify OCSP Stapling.

## Secondary options

* **`nginx.clientBodyBufferSize`:** Specifies the size and the max size of the client
request buffer. The default should be plenty generous for the vast majority of API
operations.

* **`nginx.keepAliveRequests`:** Sets the maximum number of requests that can be served 
through one keep-alive connection. After the maximum number of requests are made, the 
connection is closed. The default value is tuned so that the proxy will work correctly
behind cloud load balancers.

* **`nginx.keepAliveTimeout`:** Sets a timeout during which a keep-alive client 
connection will stay open on the server side. The default value is tuned so that 
the proxy will work correctly behind cloud load balancers.

* **`nginx.proxyConnectTimeout`:** Sets the timeout for connections to the upstream
factomd instance.

* **`nginx.requestBuffering`:** Toggles buffering of request data sent from the client
to the upstream factomd.

* **`nginx.responseBuffering`:** Toggles buffering of response data sent from an upstream factomd
to the proxy.

* **`rateLimiting.writeMethods`:** Array of JSON-RPC methods that will be considered writes
by the rate-limiting subsystem.

* **`ssl.ciphers`:** Specifies the enabled SSL ciphers. The ciphers are specified in the 
format understood by the OpenSSL library. The full list can be viewed by issuing the 
`openssl ciphers` command. The default is a very selective cipher suite that gives maximum
security.

* **`ssl.dhParam`:** Specifies the Diffie-Hellman key exchange parameters in PEM format.

## Examples

### Proxy the Factom, Inc courtesy node to port 80

#### Config file

None needed

#### Docker run command

```bash
docker run -d -p 80:8080 --name proxy bedrocksolutions/factomd-api-proxy:<tag>
```

### Proxy the Factom, Inc. courtesy node and enable CORS wildcard mode

#### Config file

```yaml

---
corsAllowOrigin: '*'
...

```

#### Docker run command

```bash
docker run -d \
  -p 80:8080 \
  -v /path/to/config.yaml:/home/app/values/config.yaml \
  --name proxy bedrocksolutions/factomd-api-proxy:<tag>
```

### Complex Example

* Proxy a factomd instance located at http://factomd.mydomain.com:8080
* Enable SSL
* Enable CORS for a specific domain

> Note: This example uses multiple config files.

#### Config files

`common.yaml`

```yaml

---
corsAllowOrigin: '^https://www\.foo\.com$'
...

```

`ssl.yaml`
```yaml

---
factomdUrl: http://factomd.mydomain.com:8080

ssl:
  certificate: |-
    -----BEGIN CERTIFICATE-----
    ...certificate goes here...
    -----END CERTIFICATE-----
    -----BEGIN CERTIFICATE-----
    ...optional root certificate in the chain goes here...
    -----END CERTIFICATE-----
  
  certificateKey: |-
    -----BEGIN PRIVATE KEY-----
    ...private key goes here...
    -----END PRIVATE KEY-----
...
```

#### Docker run command

```bash
docker run -d \
  -p 443:8443 \
  -v /path/to/config/dir:/home/app/values \
  --name proxy bedrocksolutions/factomd-api-proxy:<tag>
```

## Useful Links
      
  * [Base Image](https://hub.docker.com/r/openresty/openresty/)
  