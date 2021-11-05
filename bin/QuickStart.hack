use namespace HackHttp\Message as HM;
use namespace HackHttp\Client as HC;

<<__EntryPoint>>
function quick_start(): void 
{
  require_once(__DIR__.'/../vendor/autoload.hack');
  \Facebook\AutoloadMap\initialize();

  $client = new HC\Client();
  // Send a synchronous request.
  $response = $client->request('GET', 'https://docs.hhvm.com/hack/');

  echo $response->getStatusCode(); // 200
  echo $response->getHeaderLine('content-type'); // 'text/html'
  echo $response->getBody()->__toString(); // <!DOCTYPE html><html>...

  // Send an asynchronous request.
  $request = new HM\Request('GET', 'http://httpbin.org');
  $promise = $client->sendAsync($request)->then( (mixed $response): void ==> {
      if($response is HM\Response) {
        echo 'I completed! ' . $response->getBody()->__toString();
      }
  });

  $promise->wait();  
}