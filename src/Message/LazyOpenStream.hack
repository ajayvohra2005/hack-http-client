namespace HackHttp\Message;

use namespace HH\Lib\File;

/**
 * Lazily reads or writes to a file that is opened only after an IO operation
 * take place on the stream.
 */
final class LazyOpenStream implements StreamInterface
{
    use StreamDecoratorTrait;

    /** @var string */
    private string $file_path;

    /** @var ?File\WriteMode */
    private ?File\WriteMode $mode;

    /**
     * @param string $file_path File to lazily open
     * @param string $mode     fopen mode to use when opening the stream
     */
    public function __construct(string $file_path, ?File\WriteMode $mode=null)
    {
        $this->file_path = $file_path;
        $this->mode = $mode;
    }

    /**
     * Creates the underlying stream lazily when required.
     */
    protected function createStream(): StreamInterface
    {
        return Utils::streamFor(Utils::getFileHandle($this->file_path, $this->mode));
    }
}
