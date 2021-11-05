namespace HackHttp\Tests\Client\Handler;

use namespace HackHttp\Client\Handler as HCH;
use type HackHttp\Message\ResponseInterface;
use type HackHttp\Tests\Helper;

class OnHeaderSucceeds implements HCH\HeaderCallbackInterface
{
    private string $expected;

    public function __construct(string $expected)
    {
        $this->expected = $expected;
    }
    public function callback(?ResponseInterface $response=null): void
    {
        if($response is nonnull) {
            Helper::assertEquals($this->expected, $response->getHeaderLine('X-Foo'));
        }
    }
}