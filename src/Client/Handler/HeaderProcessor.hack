namespace HackHttp\Client\Handler;

use HH\Lib\Vec;
use HH\Lib\Str;
use HH\Lib\C;
use HackHttp\Client\Utils;

/**
 * @internal
 */
final class HeaderProcessor
{
    /**
     * Returns the HTTP version, status code, reason phrase, and headers.
     *
     * @param vec<string> $headers
     *
     * @throws \RuntimeException
     *
     * @return dict{0:string, 1:int, 2:?string, 3:dict<string, vec<string>>}
     */
    public static function parseHeaders(vec<string> $headers): dict<arraykey, mixed>
    {
        if (!$headers) {
            throw new \RuntimeException('Expected a non-empty array of header data');
        }
        
        $version = null;
        $status = null;
        $parts = null;

        $first_line = true;

        while( (C\count($headers) > 0) && ($first_line || Str\starts_with(Str\trim($headers[0]), 'HTTP/') ) ) {
            $parts = \explode(' ', $headers[0], 3);
            $headers = Vec\drop($headers, 1);

            $version = \explode('/', $parts[0])[1] ?? null;
            $status = $parts[1] ?? null;
            $first_line = false;
        }
        
        if(!($parts is Container<_>) || C\count($parts) != 3) {
            throw new \RuntimeException('Invalid HTTP Response Status-Line');
        }

        if ($version === null) {
            throw new \RuntimeException('HTTP version missing from header data');
        }

        if ($status === null) {
            throw new \RuntimeException('HTTP status code missing from header data');
        }


        return dict[0 => $version, 1 => (int) $status, 2 => $parts[2] ?? null, 3 => Utils::headersFromLines($headers)];
    }
}
