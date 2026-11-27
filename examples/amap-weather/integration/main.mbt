///|
/// Calls the generated Amap client against the real HTTPS endpoint.
/// The key is passed as a process argument by run.ps1 and is never stored here.
fn arg_or(args : Array[String], index : Int, fallback : String) -> String {
  if args.length() > index { args[index] } else { fallback }
}

///|
async fn main {
  let args = @env.args()
  let key = arg_or(args, 1, "")
  if key == "" {
    abort("AMAP_KEY is required. Set it in PowerShell before running the example.")
  }
  let city = arg_or(args, 2, "110101")
  let client = @sdk.Client::new(
    api_key_name="key",
    api_key_value=key,
    api_key_location="query",
  )
  let result : Result[@sdk.WeatherResponse, @sdk.SdkError] = Ok(
    client.get_weather_info(city, extensions="base", output="JSON"),
  ) catch {
    err => Err(err)
  }
  match result {
    Ok(response) => {
      println("Amap API status: " + response.status)
      println("Amap API info: " + response.info)
      println("Live records: " + response.lives.length().to_string())
      for live in response.lives {
        println("City: " + live.city + ", weather: " + live.weather + ", temperature: " + live.temperature)
      }
    }
    Err(err) => abort(@debug.to_string(err))
  }
}
