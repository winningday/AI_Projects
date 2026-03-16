using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace Verbalize.Converters;

public class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        bool invert = parameter?.ToString() == "Invert";
        bool visible = value is bool b && b;
        if (invert) visible = !visible;
        return visible ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => value is Visibility v && v == Visibility.Visible;
}

public class InverseBoolConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => value is bool b && !b;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => value is bool b && !b;
}

public class StatusToBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is Services.AppStatus status)
        {
            return status switch
            {
                Services.AppStatus.Recording => Application.Current.FindResource("RecordingBrush"),
                Services.AppStatus.Processing => Application.Current.FindResource("ProcessingBrush"),
                Services.AppStatus.Error => Application.Current.FindResource("ErrorBrush"),
                _ => Application.Current.FindResource("TextMutedBrush")
            };
        }
        return Application.Current.FindResource("TextMutedBrush");
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotImplementedException();
}
