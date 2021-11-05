namespace HackHttp\Client\Handler;

use type HackHttp\Message\ResponseInterface;

type HeaderCallback = (function(resource, string): int);

interface HeaderCallbackInterface
{
    public function callback(?ResponseInterface $response=null): void;
}