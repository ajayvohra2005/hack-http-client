namespace HackHttp\Client\Cookie;

use HH\Lib\Vec;
use HH\Lib\Str;
use HH\Lib\C;

use HackHttp\Message\RequestInterface;
use HackHttp\Message\ResponseInterface;

/**
 * Cookie jar that stores cookies as a vec
 */
class CookieJar implements CookieJarInterface
{
    /**
     * @var vec<SetCookie> Loaded cookie data
     */
    private vec<SetCookie> $cookies = vec[];

    /**
     * @var bool
     */
    private bool $strictMode;

    /**
     * @param bool  $strictMode  Set to true to throw exceptions when invalid
     *                           cookies are added to the cookie jar.
     * @param vec<mixed> $cookieArray Array of SetCookie objects, or dict<arraykey, mixed>
     */
    public function __construct(bool $strictMode = false, vec<mixed> $cookieArray = vec[])
    {
        $this->strictMode = $strictMode;

        foreach ($cookieArray as $cookie) {
            if ($cookie is dict<_,_>) {
                $cookie = new SetCookie($cookie);
            }

            if($cookie is SetCookie) {
                $this->setCookie($cookie);
            } else {
                throw new \RuntimeException("Cookie in cookie jar must be a SetCookie or dict");
            }
        }
    }

    /**
     * Create a new Cookie jar from a dict and domain.
     *
     * @param dict<arraykey, mixed>  $cookies Cookies to create the jar from
     * @param string $domain  Domain to set the cookies to
     */
    public static function fromArray(dict<arraykey, mixed> $cookies, string $domain): CookieJar
    {
        $cookieJar = new CookieJar();
        foreach ($cookies as $name => $value) {
            $cookieJar->setCookie(new SetCookie(dict[
                'Domain'  => $domain,
                'Name'    => $name,
                'Value'   => $value,
                'Discard' => true
            ]));
        }

        return $cookieJar;
    }

    /**
     * Evaluate if this cookie should be persisted to storage
     * that survives between requests.
     *
     * @param SetCookie $cookie              Being evaluated.
     * @param bool      $allowSessionCookies If we should persist session cookies
     */
    public static function shouldPersist(SetCookie $cookie, bool $allowSessionCookies = false): bool
    {
        if ($cookie->getExpires() || $allowSessionCookies) {
            if (!$cookie->getDiscard()) {
                return true;
            }
        }

        return false;
    }

    /**
     * Finds and returns the cookie based on the name
     *
     * @param string $name cookie name to search for
     *
     * @return SetCookie|null cookie that was found or null if not found
     */
    public function getCookieByName(string $name): ?SetCookie
    {
        foreach ($this->cookies as $cookie) {
            if ($cookie->getName() !== null && \strcasecmp($cookie->getName(), $name) === 0) {
                return $cookie;
            }
        }

        return null;
    }

    /**
     * @inheritDoc
     */
    public function toArray(): vec<dict<arraykey, mixed>>
    {
        $cb = (SetCookie $cookie): dict<arraykey, mixed> ==> $cookie->toArray();
        return Vec\map($this->cookies, $cb);
    }

    /**
     * @inheritDoc
     */
    public function clear(?string $domain = null, ?string $path = null, ?string $name = null): void
    {
        if (!$domain) {
            $this->cookies = vec[];
        } elseif (!$path) {
            $cb = (SetCookie $cookie): bool ==>  !$cookie->matchesDomain($domain);
            $this->cookies =  Vec\filter($this->cookies, $cb);
        } elseif (!$name) {
            $cb = (SetCookie $cookie): bool ==>  !($cookie->matchesPath($path) &&
                        $cookie->matchesDomain($domain));
            $this->cookies =  Vec\filter($this->cookies, $cb);
        } else {
            $cb = (SetCookie $cookie): bool ==>  !($cookie->getName() == $name &&
                        $cookie->matchesPath($path) &&
                        $cookie->matchesDomain($domain));
            $this->cookies =  Vec\filter($this->cookies, $cb);
        }
    }

    /**
     * @inheritDoc
     */
    public function clearSessionCookies(): void
    {
        $cb = (SetCookie $cookie): bool ==> !$cookie->getDiscard() && $cookie->getExpires();
        $this->cookies = Vec\filter($this->cookies, $cb);
    }

    /**
     * @inheritDoc
     */
    public function setCookie(SetCookie $cookie): bool
    {
        // If the name string is empty (but not 0), ignore the set-cookie
        // string entirely.
        $name = $cookie->getName();
        if (!$name && $name !== '0') {
            return false;
        }

        // Only allow cookies with set and valid domain, name, value
        $result = $cookie->validate();
        if ($result is string) {
            if ($this->strictMode) {
                throw new \RuntimeException('Invalid cookie: ' . $result);
            }
            $this->removeCookieIfEmpty($cookie);
            return false;
        }

        // Resolve conflicts with previously set cookies
        foreach ($this->cookies as $c) {

            // Two cookies are identical, when their path, and domain are
            // identical.
            if ($c->getPath() != $cookie->getPath() ||
                $c->getDomain() != $cookie->getDomain() ||
                $c->getName() != $cookie->getName()
            ) {
                continue;
            }

            // The previously set cookie is a discard cookie and this one is
            // not so allow the new cookie to be set
            $cb = (SetCookie $v): bool ==> ($v !== $c);

            $cookie_expires = $cookie->getExpires();
            $c_expires = $c->getExpires();

            if ( (!$cookie->getDiscard() && $c->getDiscard()) ||
                ($cookie_expires is int && $c_expires is int && $cookie_expires > $c_expires) ||
                ($cookie->getValue() !== $c->getValue())) {
                    $this->cookies = Vec\filter($this->cookies, $cb);
                    continue;
            }

            // The cookie exists, so no need to continue
            return false;
        }

        $this->cookies[] = $cookie;

        return true;
    }

    public function count(): int
    {
        return C\count($this->cookies);
    }

    /**
     * @return \ArrayIterator<SetCookie>
     */
    public function getIterator(): \ArrayIterator<SetCookie>
    {
        return new \ArrayIterator(\array_values($this->cookies));
    }

    public function extractCookies(RequestInterface $request, ResponseInterface $response): void
    {
        $cookieHeader = $response->getHeader('Set-Cookie');

        if ($cookieHeader) {
            foreach ($cookieHeader as $cookie) {
                $sc = SetCookie::fromString($cookie);
                if (!$sc->getDomain()) {
                    $sc->setDomain($request->getUri()->getHost());
                }
                if (0 !== Str\search($sc->getPath(), '/')) {
                    $sc->setPath($this->getCookiePathFromRequest($request));
                }
                $this->setCookie($sc);
            }
        }
    }

    /**
     * Computes cookie path following RFC 6265 section 5.1.4
     *
     * @link https://tools.ietf.org/html/rfc6265#section-5.1.4
     */
    private function getCookiePathFromRequest(RequestInterface $request): string
    {
        $uriPath = $request->getUri()->getPath();
        if ('' === $uriPath) {
            return '/';
        }
        if (0 !== Str\search($uriPath, '/')) {
            return '/';
        }
        if ('/' === $uriPath) {
            return '/';
        }
        $lastSlashPos = Str\search_last($uriPath, '/');
        if (0 === $lastSlashPos || $lastSlashPos is null) {
            return '/';
        }

        return Str\slice($uriPath, 0, $lastSlashPos);
    }

    public function withCookieHeader(RequestInterface $request): RequestInterface
    {
        $values = vec[];
        $uri = $request->getUri();
        $scheme = $uri->getScheme();
        $host = $uri->getHost();
        $path = $uri->getPath() ?: '/';

        foreach ($this->cookies as $cookie) {
            if ($cookie->matchesPath($path) &&
                $cookie->matchesDomain($host) &&
                !$cookie->isExpired() &&
                (!$cookie->getSecure() || $scheme === 'https')
            ) {
                $values[] = $cookie->getName() . '='
                    . (string)$cookie->getValue();
            }
        }

        if($values) {
            $value =  $request->withHeader('Cookie', vec[\implode('; ', $values)]);
            if($value is RequestInterface) {
                return $value;
            }
        } 
            
        return $request;
        
    }

    /**
     * If a cookie already exists and the server asks to set it again with a
     * null value, the cookie must be deleted.
     */
    private function removeCookieIfEmpty(SetCookie $cookie): void
    {
        $cookieValue = $cookie->getValue();
        if ($cookieValue === null || $cookieValue === '') {
            $this->clear(
                $cookie->getDomain(),
                $cookie->getPath(),
                $cookie->getName()
            );
        }
    }
}
