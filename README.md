# Hack HTTP client

## Overview

This project implements an HTTP Client in [Hack](https://docs.hhvm.com/hack/).

- Simple HTTP Client interface 
- Synchronous and asynchronous requests 
- Middleware support

## Requirements

HHVM 4.132 and above.

## Installation

* Git clone this repository
* Install [composer](https://getcomposer.org/)
* In the root directory of this repository, run the command
  
        composer install

To use this package,

        composer require ajayvohra2005/hack-http
        
## Running Tests
Testing uses a mock HTTP server written in [Node.js](https://nodejs.org/en/). The project was tested with Node.js version v17.0.1. After installation of Node.js and this project, run the following command in the root directory of this repository:

        ./vendor/bin/hacktest tests/
    
## Quick Start Example

```
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
```
## License

Hack Http package is made available under the MIT License (MIT). Please see [License File](LICENSE) for more information.

## Acknowledgements
The [Guzzle, PHP HTTP Client](https://github.com/guzzle/guzzle) and [PSR-7 Message Implementation](https://github.com/guzzle/psr7) projects inspired this code. 
