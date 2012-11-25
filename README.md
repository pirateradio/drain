# drain

Log drain to send metrics from Papertrail to Librato

## Usage

* Deploy as a Heroku app, set `LIBRATO_EMAIL` and `LIBRATO_TOKEN`
* Point a Papertrail Webhook at the app

## Logs

Logs should be in a structured log format, including the `measure`, `value` or `val`, and `units` keys.

    measure="metric.name" value="5" units="ms"

If not specified, the following defaults will be applied:
  * `value`: `1`
  * `units`: `count`

## License

MIT
