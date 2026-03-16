using System.Windows;
using Verbalize.Services;

namespace Verbalize.Views;

public partial class OnboardingWindow : Window
{
    private readonly AppState _appState = AppState.Instance;
    private int _currentStep;

    public OnboardingWindow()
    {
        InitializeComponent();
    }

    private void Next_Click(object sender, RoutedEventArgs e)
    {
        if (_currentStep == 0)
        {
            _currentStep = 1;
            Step1Panel.Visibility = Visibility.Collapsed;
            Step2Panel.Visibility = Visibility.Visible;
            BackBtn.Visibility = Visibility.Visible;
            NextBtn.Content = "Get Started";
            StepProgress.Value = 1;
        }
        else
        {
            // Save API keys
            var openAiKey = OnboardOpenAIKey.Password.Trim();
            var anthropicKey = OnboardAnthropicKey.Password.Trim();

            if (string.IsNullOrEmpty(openAiKey))
            {
                MessageBox.Show("Please enter your OpenAI API key. It's required for transcription.",
                    "API Key Required", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            _appState.Config.OpenAIApiKey = openAiKey;
            if (!string.IsNullOrEmpty(anthropicKey))
                _appState.Config.AnthropicApiKey = anthropicKey;

            _appState.Config.HasCompletedOnboarding = true;
            StepProgress.Value = 2;
            Close();
        }
    }

    private void Back_Click(object sender, RoutedEventArgs e)
    {
        if (_currentStep == 1)
        {
            _currentStep = 0;
            Step1Panel.Visibility = Visibility.Visible;
            Step2Panel.Visibility = Visibility.Collapsed;
            BackBtn.Visibility = Visibility.Collapsed;
            NextBtn.Content = "Next";
            StepProgress.Value = 0;
        }
    }
}
