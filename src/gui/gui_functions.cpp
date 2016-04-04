#include "../core/core_headers.h"
#include "../core/gui_core_headers.h"


void ConvertImageToBitmap(Image *input_image, wxBitmap *output_bitmap, bool auto_contrast)
{
	MyDebugAssertTrue(input_image->logical_z_dimension == 1, "Only 2D images can be used");
	MyDebugAssertTrue(output_bitmap->GetDepth() == 24, "bitmap should be 24 bit");

	float image_min_value;
	float image_max_value;
	float range;
	float inverse_range;

	int current_grey_value;
	int i, j;

	long mirror_line_address;
	long address = 0;


	if (input_image->logical_x_dimension != output_bitmap->GetWidth() || input_image->logical_y_dimension != output_bitmap->GetHeight())
	{
		output_bitmap->Create(input_image->logical_x_dimension, input_image->logical_y_dimension, 24);
	}


	if (auto_contrast == false)
	{

		input_image->GetMinMax(image_min_value, image_max_value);
	}
	else
	{
		float average_value = input_image->ReturnAverageOfRealValues();
		float variance = input_image->ReturnVarianceOfRealValues();
		float stdev = sqrt(variance);

		image_min_value = average_value - (stdev * 2.5);
		image_max_value = average_value + (stdev * 2.5);
	}

	range = image_max_value - image_min_value;
	inverse_range = 1. / range;
	inverse_range *= 256.;

	wxNativePixelData pixel_data(*output_bitmap);

	if ( !pixel_data )
	{
	   MyPrintWithDetails("Can't access bitmap data");
	   abort();
	}



	wxNativePixelData::Iterator p(pixel_data);
	p.Reset(pixel_data);

	// we have to mirror the lines as wxwidgets using 0,0 at top left

	for (j = 0; j < input_image->logical_y_dimension; j++)
	{
		mirror_line_address = (input_image->logical_y_dimension - 1 - j) * (input_image->logical_x_dimension + input_image->padding_jump_value);

		for (i = 0; i < input_image->logical_x_dimension; i++)
		{
			current_grey_value = myroundint((input_image->real_values[mirror_line_address] - image_min_value) * inverse_range);

			if (current_grey_value < 0) current_grey_value = 0;
			else
			if (current_grey_value > 255) current_grey_value = 255;

			p.Red() = current_grey_value;
			p.Green() = current_grey_value;
			p.Blue() = current_grey_value;

			p++;
			mirror_line_address++;
		}
	}

}

void GetMultilineTextExtent	(wxDC *wanted_dc, const wxString & string, int &width, int &height)
{
	wxStringTokenizer tokens(string, "\n");
	wxString current_token;
	wxSize line_size;
	int number_of_lines = tokens.CountTokens();
	int current_line;

	width = 0;
	height = 0;

	for (current_line = 0; current_line < number_of_lines; current_line++)
	{
		current_token = tokens.GetNextToken();
		line_size = wanted_dc->GetTextExtent(current_token);
		if (line_size.GetWidth() > width) width = line_size.GetWidth();
		height += line_size.GetHeight();
	}
}