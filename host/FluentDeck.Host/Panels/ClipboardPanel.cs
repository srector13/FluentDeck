using System.Text.Json.Nodes;
using FluentDeck.Core.Panels;
using FluentDeck.Host.Interop;

namespace FluentDeck.Host.Panels;

/// <summary>Text to and from the PC's clipboard. "setText" can also paste it (Ctrl+V) into the app
/// in front. Nothing is published: the clipboard is read only when the iPad asks.</summary>
internal sealed class ClipboardPanel : PanelProvider
{
    private const int MaxLength = 1_000_000;

    public override PanelDescriptor Descriptor => BuiltInPanels.Clipboard;

    public override Task StartAsync(CancellationToken ct) { Publish(new { }); return Task.CompletedTask; }

    public override async Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct)
    {
        switch (action)
        {
            case "setText":
                var text = args.OptionalString("text") ?? "";
                if (text.Length > MaxLength) throw new PanelActionException("That's too much text to send in one go.");
                await OnStaThread(() => { if (text.Length == 0) Clipboard.Clear(); else Clipboard.SetText(text); });
                if (args.Bool("paste"))
                {
                    await Task.Delay(60, ct);
                    KeyInput.SendChords([Core.Deck.KeyChord.Parse("Ctrl+V")]);
                }
                return null;
            case "getText":
                var current = await OnStaThread(() => Clipboard.ContainsText() ? Clipboard.GetText() : "");
                if (current.Length > MaxLength) current = current[..MaxLength];
                return new { text = current };
            default:
                throw UnknownAction(action);
        }
    }

    /// <summary>The Windows clipboard only talks to single-threaded apartment threads.</summary>
    private static Task<T> OnStaThread<T>(Func<T> work)
    {
        var done = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            try { done.SetResult(Retry(work)); }
            catch (Exception e) { done.SetException(new PanelActionException($"The PC's clipboard is busy: {e.Message}")); }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.IsBackground = true;
        thread.Start();
        return done.Task;
    }

    private static Task OnStaThread(Action work) => OnStaThread(() => { work(); return true; });

    /// <summary>Another app may hold the clipboard open for a moment.</summary>
    private static T Retry<T>(Func<T> work)
    {
        for (var attempt = 0; ; attempt++)
        {
            try { return work(); }
            catch (System.Runtime.InteropServices.ExternalException) when (attempt < 4) { Thread.Sleep(50); }
        }
    }
}
