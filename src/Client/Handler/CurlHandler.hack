namespace HackHttp\Client\Handler;

use namespace HH;

use HackPromises\PromiseInterface;
use HackHttp\Message\RequestInterface;
use HackHttp\Client\RequestOptions;

/**
 * HTTP handler that uses cURL easy handles as a transport layer.
 *
 * When using the CurlHandler, custom curl options can be specified as an
 * associative array of curl option constants mapping to values in the
 * **curl** key of the "client" key of the request.
 *
 * @final
 */
final class CurlHandler
{
    /**
     * @var CurlFactoryInterface
     */
    private CurlFactoryInterface $factory;

    /**
     * Accepts an associative array of options:
     *
     * - handle_factory: Optional curl factory used to create cURL handles.
     *
     * @param dict<arraykey, mixed> $options Array of options to use with the handler
     */
    public function __construct(dict<arraykey, mixed> $options = dict[])
    {
        $options_handle_factory = HH\idx($options, 'handle_factory');
        if($options_handle_factory is CurlFactoryInterface) {
            $this->factory = $options_handle_factory;
        } else {
            $this->factory = new CurlFactory();
        }
    }

    public function handle(RequestInterface $request, dict<arraykey, mixed> $options): PromiseInterface
    {
        $options_delay = HH\idx($options, RequestOptions::DELAY);

        if ($options_delay is int) {
            \usleep($options_delay * 1000);
        }

        $easy = $this->factory->create($request, $options);
        $ch = $easy->getHandle();
        if($ch is nonnull) {
            \curl_exec($ch);
            $easy->setErrno(\curl_errno($ch));
        }

        $callable = (RequestInterface $request, dict<arraykey, mixed> $options): PromiseInterface ==> {
            return $this->handle($request, $options);
        };

        return CurlFactory::finish($callable, $easy, $this->factory);
    }
}
