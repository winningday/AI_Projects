using System.Windows.Controls;
using Verbalize.Models;
using Verbalize.Services;

namespace Verbalize.Views;

public partial class StylePage : Page
{
    private readonly AppState _appState = AppState.Instance;
    private bool _loading = true;

    public StylePage()
    {
        InitializeComponent();

        var tones = Enum.GetValues<StyleTone>().Select(t => t.DisplayName()).ToArray();
        PersonalCombo.ItemsSource = tones;
        WorkCombo.ItemsSource = tones;
        EmailCombo.ItemsSource = tones;
        OtherCombo.ItemsSource = tones;

        Loaded += (_, _) =>
        {
            _loading = true;
            SetComboValue(PersonalCombo, PersonalExample, ContextType.PersonalMessages);
            SetComboValue(WorkCombo, WorkExample, ContextType.WorkMessages);
            SetComboValue(EmailCombo, EmailExample, ContextType.Email);
            SetComboValue(OtherCombo, OtherExample, ContextType.Other);
            _loading = false;
        };
    }

    private void SetComboValue(ComboBox combo, TextBlock example, ContextType context)
    {
        var tone = _appState.Config.GetStyleForContext(context);
        combo.SelectedIndex = (int)tone;
        example.Text = $"Example: \"{tone.Example()}\"";
    }

    private void SaveTone(ComboBox combo, TextBlock example, ContextType context)
    {
        if (_loading || combo.SelectedIndex < 0) return;
        var tone = (StyleTone)combo.SelectedIndex;
        _appState.Config.SetStyleForContext(context, tone);
        example.Text = $"Example: \"{tone.Example()}\"";
    }

    private void PersonalCombo_Changed(object s, SelectionChangedEventArgs e) =>
        SaveTone(PersonalCombo, PersonalExample, ContextType.PersonalMessages);
    private void WorkCombo_Changed(object s, SelectionChangedEventArgs e) =>
        SaveTone(WorkCombo, WorkExample, ContextType.WorkMessages);
    private void EmailCombo_Changed(object s, SelectionChangedEventArgs e) =>
        SaveTone(EmailCombo, EmailExample, ContextType.Email);
    private void OtherCombo_Changed(object s, SelectionChangedEventArgs e) =>
        SaveTone(OtherCombo, OtherExample, ContextType.Other);
}
