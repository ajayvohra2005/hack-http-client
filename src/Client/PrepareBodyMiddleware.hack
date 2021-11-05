namespace HackHttp\Client;

use namespace HH;
use type HH\Map;

use HackPromises\PromiseInterface;
use HackHttp\Message\RequestInterface;
use HackHttp\Message\MimeType;
use HackHttp\Message\UriInterface;
use namespace HackHttp\Message as HM;

/**
 * Prepares requests that contain a body, adding the Content-Length,
 * Content-Type, and Expect headers.
 *
 * @final
 */
class PrepareBodyMiddleware
{
    /**
     * @var RequestHandlerCallable
     */
    private RequestHandlerCallable $nextHandler;

    /**
     * @param RequestHandlerCallable $nextHandler Next handler to invoke.
     */
    public function __construct(RequestHandlerCallable $nextHandler)
    {
        $this->nextHandler = $nextHandler;
    }

    public function prepare(RequestInterface $request, dict<arraykey,  mixed> $options): PromiseInterface
    {
        $fn = $this->nextHandler;

        // Don't do anything if the request has no body.
        if ($request->getBody()->getSize() === 0) {
            return $fn($request, $options);
        }

        $modify = new Map<string, mixed>(dict[]);

        // Add a default content-type if possible.
        if (!$request->hasHeader('Content-Type')) {
            $uri = $request->getBody()->getMetadata('uri');
            if($uri is UriInterface) {
                $uri = $uri->__toString();
            }
            if ($uri is string) {
                $type = MimeType::fromFilename($uri);
                if ($type) {
                    $modify_set_headers = dict<string, mixed>[];
                    $modify_set_headers['Content-Type'] = $type;
                    $modify['set_headers'] = $modify_set_headers;
                }
            }
        }

        // Add a default content-length or transfer-encoding header.
        if (!$request->hasHeader('Content-Length') && !$request->hasHeader('Transfer-Encoding')) {
            $size = $request->getBody()->getSize();

            $modify_set_headers = HH\idx($modify, 'set_headers');
            if(!($modify_set_headers is dict<_,_>)) {
                $modify_set_headers = dict<string, mixed>[];
            }

            if ($size is nonnull) {
                $modify_set_headers['Content-Length'] = $size;
            } else {
                $modify_set_headers['Transfer-Encoding'] = 'chunked';
            }
            $modify['set_headers'] = $modify_set_headers;
        }

        // Add the expect header if needed.
        $this->addExpectHeader($request, $options, $modify);
        
        $modify_as_dict = $modify->toDArray();
        return $fn(HM\Utils::modifyRequest($request, $modify_as_dict), $options);
    }

    /**
     * Add expect header
     */
    private function addExpectHeader(RequestInterface $request, dict<arraykey,  mixed> $options, Map<string, mixed> $modify): void
    {
        // Determine if the Expect header should be used
        if ($request->hasHeader('Expect')) {
            return;
        }

        $expect = $options[RequestOptions::EXPECT] ?? null;

        // Return if disabled or if you're not using HTTP/1.1 or HTTP/2.0
        if ($expect === false || \floatval($request->getProtocolVersion()) < 1.1) {
            return;
        }

        // The expect header is unconditionally enabled
        if ($expect === true) {
            $modify_set_headers = HH\idx($modify, 'set_headers');
            if(!($modify_set_headers is dict<_,_>)) {
                $modify_set_headers = dict<string, mixed>[];
            }
            $modify_set_headers['Expect'] = '100-Continue';
            $modify['set_headers'] = $modify_set_headers;
            return;
        }

        // By default, send the expect header when the payload is > 1mb
        if ($expect === null) {
            $expect = 1048576;
        }

        // Always add if the body cannot be rewound, the size cannot be
        // determined, or the size is greater than the cutoff threshold
        $body = $request->getBody();
        $size = $body->getSize();

        if ($size is null || ($size is int && $expect is int && $size >= $expect) || !$body->isSeekable()) {
            $modify_set_headers = HH\idx($modify, 'set_headers');
            if(!($modify_set_headers is dict<_,_>)) {
                $modify_set_headers = dict<string, mixed>[];
            }
            $modify_set_headers['Expect'] = '100-Continue';
            $modify['set_headers'] = $modify_set_headers;
        }
    }
}
