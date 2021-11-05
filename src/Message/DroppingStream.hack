namespace HackHttp\Message;

use namespace HH\Lib\Str;

/**
 * Stream decorator that begins dropping data once the size of the underlying
 * stream becomes too full.
 */
final class DroppingStream implements StreamInterface
{
    use StreamDecoratorTrait;

    /** @var int */
    private int $maxLength;

    /**
     * @param StreamInterface $stream    Underlying stream to decorate.
     * @param int             $maxLength Maximum size before dropping data.
     */
    public function __construct(StreamInterface $stream, int $maxLength)
    {
        $this->stream = $stream;
        $this->maxLength = $maxLength;
    }

    public function write(string $string): int
    {
        $_stream = $this->stream;

        if($_stream is nonnull) {
            $stream_size = $_stream->getSize();

            if($stream_size is nonnull) {
                $diff = $this->maxLength - $stream_size;

                // Begin returning 0 when the underlying stream is too large.
                if ($diff <= 0) {
                    return 0;
                }

                // Write the stream or a subset of the stream if needed.
                if (\strlen($string) < $diff) {
                    return $_stream->write($string);
                }

                return $_stream->write(Str\slice($string, 0, $diff));
            }
        }

        return 0;
    }
}
