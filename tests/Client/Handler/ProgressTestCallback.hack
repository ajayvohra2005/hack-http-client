namespace HackHttp\Tests\Client\Handler;

use HackHttp\Tests\Helper;
use HackHttp\Tests\Server;

use HackHttp\Client\Handler\ProgressCallbackInterface;


use namespace HH\Lib\OS;
use namespace HH\Lib\C;

class ProgressTestCallback implements ProgressCallbackInterface
{
    private bool $called=false;

    public function callback(mixed...$args): void
    {
        $this->called = true;
    }

    public function isCalled(): bool
    {
        return $this->called;
    }
}