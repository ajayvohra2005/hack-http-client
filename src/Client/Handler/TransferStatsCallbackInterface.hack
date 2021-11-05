namespace HackHttp\Client\Handler;

use type HackHttp\Client\TransferStats;

interface TransferStatsCallbackInterface
{
    public function callback(TransferStats $stats): void;
}