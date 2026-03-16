// Module: Self-learning correction tracker — detects user edits after text injection
using System.Runtime.InteropServices;

namespace Verbalize.Services;

public class CorrectionTracker
{
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

    private readonly ConfigManager _config;
    private CancellationTokenSource? _cts;

    public CorrectionTracker(ConfigManager config)
    {
        _config = config;
    }

    public void StartTracking(string injectedText)
    {
        _cts?.Cancel();
        _cts = new CancellationTokenSource();
        var token = _cts.Token;

        Task.Run(async () =>
        {
            try
            {
                // Wait for paste to complete
                await Task.Delay(150, token);

                // Wait for user to potentially edit
                await Task.Delay(5000, token);

                // This is a simplified version — on Windows, reading arbitrary text fields
                // from other apps requires UI Automation, which is complex. For now, we track
                // corrections through the transcript history UI where users can edit.
            }
            catch (OperationCanceledException) { }
        }, token);
    }

    public void CancelTracking()
    {
        _cts?.Cancel();
    }

    public void RecordManualCorrection(string original, string corrected)
    {
        if (string.IsNullOrWhiteSpace(original) || string.IsNullOrWhiteSpace(corrected))
            return;

        var originalWords = original.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var correctedWords = corrected.Split(' ', StringSplitOptions.RemoveEmptyEntries);

        // Simple word-level diff using LCS alignment
        var lcs = LongestCommonSubsequence(originalWords, correctedWords);
        int oi = 0, ci = 0, li = 0;

        while (oi < originalWords.Length && ci < correctedWords.Length)
        {
            if (li < lcs.Length && originalWords[oi] == lcs[li] && correctedWords[ci] == lcs[li])
            {
                oi++; ci++; li++;
            }
            else if (li < lcs.Length && originalWords[oi] != lcs[li] && correctedWords[ci] != lcs[li])
            {
                // Substitution — potential correction
                if (LevenshteinSimilarity(originalWords[oi], correctedWords[ci]) > 0.4)
                {
                    _config.AddCorrection(originalWords[oi], correctedWords[ci]);

                    if (_config.AutoAddToDictionary)
                        _config.AddDictionaryEntry(correctedWords[ci], "auto");
                }
                oi++; ci++;
            }
            else if (li < lcs.Length && originalWords[oi] == lcs[li])
            {
                ci++; // insertion in corrected
            }
            else
            {
                oi++; // deletion from original
            }
        }
    }

    private static string[] LongestCommonSubsequence(string[] a, string[] b)
    {
        int m = a.Length, n = b.Length;
        var dp = new int[m + 1, n + 1];

        for (int i = 1; i <= m; i++)
            for (int j = 1; j <= n; j++)
                dp[i, j] = a[i - 1] == b[j - 1]
                    ? dp[i - 1, j - 1] + 1
                    : Math.Max(dp[i - 1, j], dp[i, j - 1]);

        var result = new List<string>();
        int x = m, y = n;
        while (x > 0 && y > 0)
        {
            if (a[x - 1] == b[y - 1])
            {
                result.Add(a[x - 1]);
                x--; y--;
            }
            else if (dp[x - 1, y] > dp[x, y - 1])
                x--;
            else
                y--;
        }

        result.Reverse();
        return result.ToArray();
    }

    private static double LevenshteinSimilarity(string a, string b)
    {
        if (string.IsNullOrEmpty(a) || string.IsNullOrEmpty(b)) return 0;

        int m = a.Length, n = b.Length;
        var dp = new int[m + 1, n + 1];

        for (int i = 0; i <= m; i++) dp[i, 0] = i;
        for (int j = 0; j <= n; j++) dp[0, j] = j;

        for (int i = 1; i <= m; i++)
            for (int j = 1; j <= n; j++)
            {
                int cost = a[i - 1] == b[j - 1] ? 0 : 1;
                dp[i, j] = Math.Min(Math.Min(dp[i - 1, j] + 1, dp[i, j - 1] + 1), dp[i - 1, j - 1] + cost);
            }

        int maxLen = Math.Max(m, n);
        return 1.0 - (double)dp[m, n] / maxLen;
    }
}
