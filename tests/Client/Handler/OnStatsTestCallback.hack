namespace HackHttp\Tests\Client\Handler;

use  HackHttp\Client\TransferStats;
use  HackHttp\Client\Handler\TransferStatsCallbackInterface;

class OnStatsTestCallback implements TransferStatsCallbackInterface
{
    private ?TransferStats $stats;

    public function callback(TransferStats $stats): void
    {
        $this->stats = $stats;
    }

    public function getStats(): ?TransferStats
    {
        return $this->stats;
    }
}