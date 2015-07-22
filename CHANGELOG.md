#Change Log

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