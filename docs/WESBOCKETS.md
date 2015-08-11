# GRHttp - A native Ruby Generic HTTP and WebSocket server.

GRHttp's Websocket capabilities are designed for ease of use and utilization, as well as a low learning curve.

Since websockets required you to learn about the Javascript's websockets API, GRHttp followed on with the same spirit, utilizing known callback such as: #on_open, #on_message and #on_close, as well as new callbacks such as #on_broadcast.

## To Do: Write a Websocket demo and short explanation

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake false` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/boazsegev/grhttp.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

