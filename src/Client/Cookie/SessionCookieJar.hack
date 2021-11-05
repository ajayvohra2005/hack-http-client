namespace HackHttp\Client\Cookie;

/**
 * Persists cookies in the client session
 */
class SessionCookieJar extends CookieJar
{
    public static  dict<string, string> $_SESSION = dict[];

    /**
     * @var string session key
     */
    private string $sessionKey;

    /**
     * @var bool Control whether to persist session cookies or not.
     */
    private bool $storeSessionCookies;

    /**
     * Create a new SessionCookieJar object
     *
     * @param string $sessionKey          Session key name to store the cookie
     *                                    data in session
     * @param bool   $storeSessionCookies Set to true to store session cookies
     *                                    in the cookie jar.
     */
    public function __construct(string $sessionKey, bool $storeSessionCookies = false)
    {
        parent::__construct();
        $this->sessionKey = $sessionKey;
        $this->storeSessionCookies = $storeSessionCookies;
        $this->load();
    }

    /**
     * Save cookies to the client session
     */
    public function save(): void
    {
        $json = vec[];
        /** @var SetCookie $cookie */
        foreach ($this as $cookie) {
            if (CookieJar::shouldPersist($cookie, $this->storeSessionCookies)) {
                $json[] = $cookie->toArray();
            }
        }

        self::$_SESSION[$this->sessionKey] = \json_encode($json);
    }

    /**
     * Load the contents of the client session into the data array
     */
    protected function load(): void
    {
        if (!isset(self::$_SESSION[$this->sessionKey])) {
            return;
        }
        $data = \json_decode(self::$_SESSION[$this->sessionKey], true);
        if ($data is Traversable<_>) {
            foreach ($data as $cookie) {
                if($cookie is dict<_,_>) {
                    $this->setCookie(new SetCookie($cookie));
                }
            }
        } elseif (\strlen($data)) {
            throw new \RuntimeException("Invalid cookie data");
        }
    }
}
