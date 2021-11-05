namespace HackHttp\Tests\Client\Handler;

use namespace HackHttp\Client\Handler as HCH;
use type HackHttp\Message\ResponseInterface;

class OnHeaderFails implements HCH\HeaderCallbackInterface
{
    public function callback(?ResponseInterface $response=null): void
    {
        throw new \Exception('test');
    }
}