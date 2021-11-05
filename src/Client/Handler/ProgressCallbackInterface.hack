namespace HackHttp\Client\Handler;


interface ProgressCallbackInterface
{
    public function callback(mixed... $args): void;
}