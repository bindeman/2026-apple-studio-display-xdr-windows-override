using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace StudioDisplayXdr.App;

public partial class App : System.Windows.Application
{
    private const string InstanceMutexName = @"Local\StudioDisplayXdr.App.Instance";
    private const string ShowEventName = @"Local\StudioDisplayXdr.App.Show";

    private Mutex? _instanceMutex;
    private EventWaitHandle? _showEvent;
    private Thread? _showEventThread;
    private bool _isExiting;

    public static bool StartMinimized { get; private set; }

    protected override void OnStartup(StartupEventArgs e)
    {
        ShutdownMode = ShutdownMode.OnExplicitShutdown;

        StartMinimized = e.Args.Any(arg =>
            arg.Equals("--minimized", StringComparison.OrdinalIgnoreCase) ||
            arg.Equals("/minimized", StringComparison.OrdinalIgnoreCase));

        if (!TryClaimSingleInstance())
        {
            Shutdown();
            return;
        }

        RenderOptions.ProcessRenderMode = RenderMode.SoftwareOnly;
        base.OnStartup(e);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _isExiting = true;
        _showEvent?.Set();
        _showEventThread?.Join(millisecondsTimeout: 1000);
        _showEventThread = null;
        _showEvent?.Dispose();
        _showEvent = null;

        try
        {
            _instanceMutex?.ReleaseMutex();
        }
        catch (ApplicationException)
        {
        }

        _instanceMutex?.Dispose();
        _instanceMutex = null;

        base.OnExit(e);
    }

    private bool TryClaimSingleInstance()
    {
        _instanceMutex = new Mutex(initiallyOwned: true, InstanceMutexName, out var createdNew);
        if (!createdNew)
        {
            SignalExistingInstance();
            _instanceMutex.Dispose();
            _instanceMutex = null;
            return false;
        }

        _showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
        _showEventThread = new Thread(ShowEventLoop)
        {
            IsBackground = true,
            Name = "Studio Display XDR show event listener"
        };
        _showEventThread.Start();

        return true;
    }

    private void ShowEventLoop()
    {
        while (!_isExiting)
        {
            var handle = _showEvent;
            if (handle is null)
            {
                return;
            }

            handle.WaitOne();
            if (_isExiting)
            {
                return;
            }

            Dispatcher.BeginInvoke(ShowExistingWindow, DispatcherPriority.Send);
        }
    }

    private static void SignalExistingInstance()
    {
        try
        {
            using var showEvent = EventWaitHandle.OpenExisting(ShowEventName);
            showEvent.Set();
        }
        catch (WaitHandleCannotBeOpenedException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private static void ShowExistingWindow()
    {
        if (Current.MainWindow is MainWindow window)
        {
            window.ShowFromExternalLaunch();
        }
    }
}
