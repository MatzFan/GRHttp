#Change Log

***

Change log v.0.0.18

**Fix**: Fixed an issue with the method used to extract data into the params (or cookie) Hash. The issue caused an exception to be raised but the correct value to be placed in the Hash.

***

Change log v.0.0.17

**Fix**: Fixed a typo in the GRHttp's Rack variable naming (was `pl.cookies` instead of `gr.cookies`, same issue with `gr.params`).

**Update**: better Rack support.

***

Change log v.0.0.16

**Fix**: GRHttp will better respect requests from HTTP/1 or with the header 'Connection: close'.

***

Change log v.0.0.15

**Wow**: This is GRHttp's first version as a Dual-Rack-GRHttp server - this means you can use GRHttp both as a Rack server (with all of Rack's limitations) while using GRHttp's native features outside of Rack at the same time (see the [README]{README.md}) for more details.

***

Change log v.0.0.14

**update**: attempts to encode incoming data as UTF8 when the encoding conforms.

***

Change log v.0.0.13

**performance**: clears HTTP and Websocket parsing (and logging) memory faster.

**update**: requires the updated GReactor (v.0.0.11)

***

Change log v.0.0.12

**update**: requires the updated GReactor (v.0.0.10)

***

Change log v.0.0.11

**Fix**: Fixed an issue where websockets might be answerwed if the response was sent and the update_handler return true (using the `response.finish`).

***

Change log v.0.0.10

**Fix**: Fixed an issue where the last byte of an incoming Websocket message wouldn't be unmasked - resulting in corrupt data.

***

Change log v.0.0.9

Changelog will start loging after the first release that will be viable for production testing.

For now, this version introduces great performance upgrade and some minor bug fixes for the Websocket protocol handling.