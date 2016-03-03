#include "core_headers.h"

void LS_POLY(float *x_data, float *y_data, int number_of_points, int order_of_polynomial, float *output_smoothed_curve, float *output_coefficients);

Curve::Curve()
{
	have_polynomial = false;
	have_savitzky_golay = false;

	number_of_points = 0;
	allocated_space_for_points = 100;

	data_x = new float[100];
	data_y = new float[100];

	polynomial_fit = NULL; // allocate on fit..
	savitzky_golay_fit = NULL;

	polynomial_order = 0;
	polynomial_coefficients = NULL;

	savitzky_golay_polynomial_order = 0;
	savitzky_golay_window_size = 0;
}

Curve::~Curve()
{
	delete [] data_x;
	delete [] data_y;

	if (have_polynomial == true)
	{
		delete [] polynomial_fit;
		delete [] polynomial_coefficients;
	}

	if (have_savitzky_golay == true)
	{
		delete [] savitzky_golay_fit;
	}
}

Curve & Curve::operator = (const Curve *other_curve)
{
	  // Check for self assignment
	   if(this != other_curve)
	   {
		   int counter;

		   if (number_of_points != other_curve->number_of_points)
		   {
			   delete [] data_x;
			   delete [] data_y;

			   allocated_space_for_points = other_curve->allocated_space_for_points;

			   data_x = new float[allocated_space_for_points];
			   data_y = new float[allocated_space_for_points];

			   polynomial_order = other_curve->polynomial_order;

			   if (have_polynomial == true)
			   {
				   delete [] polynomial_fit;
				   delete [] polynomial_coefficients;
			   }

			   if (have_savitzky_golay == true)
			   {
				   delete [] savitzky_golay_fit;
			   }

			   if (other_curve->have_polynomial == true)
			   {
				   polynomial_fit = new float[number_of_points];
				   polynomial_coefficients = new float[polynomial_order];
			   }

			   if (other_curve->have_savitzky_golay == true)
			   {
				   savitzky_golay_fit = new float[number_of_points];
			   }


		   }
		   else
		   {
			   polynomial_order = other_curve->polynomial_order;

			   if (have_polynomial != other_curve->have_polynomial)
			   {
				   if (have_polynomial == true)
				   {
					   delete [] polynomial_coefficients;
					   delete [] polynomial_fit;
				   }
				   else
				   {
					   polynomial_fit = new float[number_of_points];
					   polynomial_coefficients = new float[polynomial_order];
				   }

			   }

			   if (have_savitzky_golay != other_curve->have_savitzky_golay)
			   {
				   if (have_savitzky_golay == true)
				   {
					   delete [] savitzky_golay_fit;
				   }
				   else
				   {
					   savitzky_golay_fit = new float[number_of_points];
				   }
			   }
		   }


		   number_of_points = other_curve->number_of_points;
		   have_polynomial = other_curve->have_polynomial;
		   have_savitzky_golay = other_curve->have_savitzky_golay;
		   savitzky_golay_polynomial_order = other_curve->savitzky_golay_polynomial_order;
		   savitzky_golay_window_size = other_curve->savitzky_golay_window_size;

		   for (counter = 0; counter < number_of_points; counter++)
		   {
		      data_x[counter] = other_curve->data_x[counter];
		      data_y[counter] = other_curve->data_y[counter];
		   }

		   if (have_polynomial == true)
		   {
			   for (counter = 0; counter < number_of_points; counter++)
			   {
			      polynomial_fit[counter] = other_curve->polynomial_fit[counter];
			   }

			   for (counter = 0; counter < polynomial_order; counter++)
			   {
				   polynomial_coefficients[counter] = other_curve->polynomial_coefficients[counter];
			   }

		   }

		   if (have_savitzky_golay == true)
		   {
			   for (counter = 0; counter < number_of_points; counter++)
			   {
			      savitzky_golay_fit[counter] = other_curve->savitzky_golay_fit[counter];
			   }
		   }
	   }

	   return *this;
}

Curve & Curve::operator = (const Curve &other_curve)
{
	*this = &other_curve;
	return *this;
}

void Curve::ResampleCurve(Curve *input_curve, int wanted_number_of_points)
{
	MyDebugAssertTrue(input_curve->number_of_points > 0, "Input curve is empty");
	MyDebugAssertTrue(wanted_number_of_points > 1, "wanted_number_of_points is smaller than 2");

	Curve temp_curve;

	float i_x;

	for (int i = 0; i < wanted_number_of_points; i++)
	{
		i_x = float(i * number_of_points) / float(wanted_number_of_points) * (1.0 - 1.0 / float(wanted_number_of_points - 1));
		temp_curve.AddPoint(i_x, input_curve->ReturnLinearInterpolationFromI(i_x));
	}

	CopyFrom(&temp_curve);
}

float Curve::ReturnLinearInterpolationFromI(float wanted_i)
{
	MyDebugAssertTrue(number_of_points > 0, "No points to interpolate");
	MyDebugAssertTrue(wanted_i <= number_of_points - 1, "Index too high");
	MyDebugAssertTrue(wanted_i >= 0, "Index too low");

	int i = int(wanted_i);

	float distance_below = wanted_i - i;
	float distance_above = 1.0 - distance_below;
	float distance;

	if (distance_below == 0.0) return data_y[i];
	if (distance_above == 0.0) return data_y[i + 1];

	return (1.0 - distance_above) * data_y[i + 1] + (1.0 - distance_below) * data_y[i];
}

float Curve::ReturnLinearInterpolationFromX(float wanted_x_value)
{
	MyDebugAssertTrue(number_of_points > 0, "No points to interpolate");

	int closest_x_below;
	int closest_x_above;

	float closest_distance_below = std::numeric_limits<float>::max();
	float closest_distance_above = std::numeric_limits<float>::max();
	float distance;

	for (int i = 0; i < number_of_points; i++)
	{
		distance = fabs(data_x[i] - wanted_x_value);
		if (data_x[i] <= wanted_x_value && distance < closest_distance_below)
		{
			closest_x_below = i;
			closest_distance_below = distance;
		}
		if (data_x[i] >= wanted_x_value && distance < closest_distance_above)
		{
			closest_x_above = i;
			closest_distance_above = distance;
		}
	}

	// wanted_x_value is outside range. Assign closest value
	if (closest_x_below == closest_x_above) return data_y[closest_x_below];

	// Otherwise, return interpolated value
	distance = data_x[closest_x_above] - data_x[closest_x_below];
	if (distance == 0) return (data_y[closest_x_below] + data_y[closest_x_above]) / 2.0;
	return ((distance - closest_distance_above) * data_y[closest_x_above] + (distance - closest_distance_below) * data_y[closest_x_below]) / distance;
}

void Curve::PrintToStandardOut()
{
	for (int i = 0; i < number_of_points; i++)
	{
		wxPrintf("%f,%f\n",data_x[i],data_y[i]);
	}
}

void Curve::WriteToFile(wxString output_file)
{
	MyDebugAssertTrue(number_of_points > 0, "Curve is empty");

	float temp_float[2];

	NumericTextFile output_curve_file(output_file, OPEN_TO_WRITE, 2);
	output_curve_file.WriteCommentLine("C            X              Y");
	for (int i = 1; i < number_of_points; i++)
	{
		temp_float[0] = data_x[i];
		temp_float[1] = data_y[i];

		output_curve_file.WriteLine(temp_float);
	}
}

void Curve::CopyFrom(Curve *other_curve)
{
	*this = other_curve;
}

void Curve::CheckMemory()
{
	if (number_of_points >= allocated_space_for_points)
	{
		// reallocate..

		if (allocated_space_for_points < 10000) allocated_space_for_points *= 2;
		else allocated_space_for_points += 10000;

		float *x_buffer = new float[allocated_space_for_points];
		float *y_buffer = new float[allocated_space_for_points];

		for (long counter = 0; counter < number_of_points; counter++)
		{
			x_buffer[counter] = data_x[counter];
			y_buffer[counter] = data_y[counter];
		}

		delete [] data_x;
		delete [] data_y;

		data_x = x_buffer;
		data_y = y_buffer;
	}
}

void Curve::AddPoint(float x_value, float y_value)
{
	// check memory

	CheckMemory();

	// add the point

	data_x[number_of_points] = x_value;
	data_y[number_of_points] = y_value;

	number_of_points++;
}

void Curve::ClearData()
{
	number_of_points = 0;

	if (have_polynomial == true)
	{
		delete [] polynomial_fit;
		delete [] polynomial_coefficients;

		have_polynomial = false;
	}

	if (have_savitzky_golay == true)
	{
		delete [] savitzky_golay_fit;

		have_savitzky_golay = false;
	}
}

void Curve::FitSavitzkyGolayToData(int wanted_window_size, int wanted_polynomial_order)
{
	// make sure the window size is odd

	MyDebugAssertTrue(IsOdd(wanted_window_size) == true, "Window must be odd!")
	MyDebugAssertTrue(wanted_window_size < number_of_points, "Window size is larger than the number of points!");
	MyDebugAssertTrue(polynomial_order < wanted_window_size, "polynomial order is larger than the window size!");

	int pixel_counter;
	int polynomial_counter;

	int end_start;

	int half_pixel = wanted_window_size / 2;

	float *fit_array_x = new float[wanted_window_size];
	float *fit_array_y = new float[wanted_window_size];
	float *output_fit_array = new float[wanted_window_size];
	float *coefficient_array = new float[wanted_polynomial_order];

	if (have_savitzky_golay == true)
	{
		delete [] savitzky_golay_fit;
	}

	savitzky_golay_fit = new float[number_of_points];
	have_savitzky_golay = true;

	savitzky_golay_polynomial_order = wanted_polynomial_order;
	savitzky_golay_window_size = wanted_window_size;

	// loop over all the points..

	for (pixel_counter = 0; pixel_counter < number_of_points - 2 * half_pixel; pixel_counter++ )
	{
		// for this pixel, extract the window, fit the polynomial, and copy the average into the output array

		for (polynomial_counter = 0; polynomial_counter < wanted_window_size; polynomial_counter++)
		{
			fit_array_x[polynomial_counter] = data_x[pixel_counter + polynomial_counter];
			fit_array_y[polynomial_counter] = data_y[pixel_counter + polynomial_counter];
		}

		// fit a polynomial to this data..

		LS_POLY(fit_array_x, fit_array_y, wanted_window_size, wanted_polynomial_order, output_fit_array, coefficient_array);

		// take the middle pixel, and put it into the output array..

		savitzky_golay_fit[half_pixel + pixel_counter] = output_fit_array[half_pixel];
	}

	// now we need to take care of the ends - first the start..

	for (polynomial_counter = 0; polynomial_counter < wanted_window_size; polynomial_counter++)
	{
		fit_array_x[polynomial_counter] = data_x[polynomial_counter];

		if (polynomial_counter < half_pixel) fit_array_y[polynomial_counter] = data_y[polynomial_counter];
		else fit_array_y[polynomial_counter] = savitzky_golay_fit[polynomial_counter];
	}

	// fit a polynomial to this data..

	LS_POLY(fit_array_x, fit_array_y, wanted_window_size, wanted_polynomial_order, output_fit_array, coefficient_array);

	// copy the required data back..

	for (polynomial_counter = 0; polynomial_counter < half_pixel; polynomial_counter++)
	{
		savitzky_golay_fit[polynomial_counter] = output_fit_array[polynomial_counter];
	}


	// now the end..

	end_start = number_of_points - (wanted_window_size + 1);
	pixel_counter = 0;

	for (polynomial_counter = end_start; polynomial_counter < number_of_points; polynomial_counter++)
	{
		fit_array_x[pixel_counter] = data_x[polynomial_counter];

		if (pixel_counter > half_pixel) fit_array_y[pixel_counter] = data_y[polynomial_counter];
		else fit_array_y[pixel_counter] = savitzky_golay_fit[polynomial_counter];

		pixel_counter++;
	}

	// fit a polynomial to this data..

	LS_POLY(fit_array_x, fit_array_y, wanted_window_size, wanted_polynomial_order, output_fit_array, coefficient_array);

	// copy the required data back..

	pixel_counter = half_pixel + 1;

	for (polynomial_counter = number_of_points - half_pixel; polynomial_counter < number_of_points; polynomial_counter++)
	{
		savitzky_golay_fit[polynomial_counter] = output_fit_array[pixel_counter];
		pixel_counter++;
	}


	delete [] fit_array_x;
	delete [] fit_array_y;
	delete [] output_fit_array;
	delete [] coefficient_array;
}

void Curve::FitPolynomialToData(int wanted_polynomial_order)
{
	if (have_polynomial == true)
	{
		delete [] polynomial_coefficients;
		delete [] polynomial_fit;
	}

	polynomial_fit = new float[number_of_points];
	polynomial_order = wanted_polynomial_order;
	polynomial_coefficients = new float[polynomial_order];
	have_polynomial = true;

	LS_POLY(data_x, data_y, number_of_points, polynomial_order, polynomial_fit, polynomial_coefficients); // weird old code to do the fit
}



/***************************************************
*      Program to demonstrate least squares        *
*         polynomial fitting subroutine            *
* ------------------------------------------------ *
* Reference: BASIC Scientific Subroutines, Vol. II *
* By F.R. Ruckdeschel, BYTE/McGRAWW-HILL, 1981 [1].*
*                                                  *
*                C++ version by J-P Moreau, Paris  *
*                       (www.jpmoreau.fr)          *
* ------------------------------------------------ *

typedef double TAB[SIZE+1];

int    i,l,m,n;
double dd,e1,vv;

TAB    x,y,v,a,b,c,d,c2,e,f;



/****************************************************************
*         LEAST SQUARES POLYNOMIAL FITTING SUBROUTINE           *
* ------------------------------------------------------------- *
* This program least squares fits a polynomial to input data.   *
* forsythe orthogonal polynomials are used in the fitting.      *
* The number of data points is n.                               *
* The data is input to the subroutine in x[i], y[i] pairs.      *
* The coefficients are returned in c[i],                        *
* the smoothed data is returned in v[i],                        *
* the order of the fit is specified by m.                       *
* The standard deviation of the fit is returned in d.           *
* There are two options available by use of the parameter e:    *
*  1. if e = 0, the fit is to order m,                          *
*  2. if e > 0, the order of fit increases towards m, but will  *
*     stop if the relative standard deviation does not decrease *
*     by more than e between successive fits.                   *
* The order of the fit then obtained is l.                      *
****************************************************************/
/*
void Curve::LS_POLY()
{

	double a[polynomial_order + 2];//
	double b[polynomial_order + 2];//
	double c[polynomial_order + 3];
	double c2[polynomial_order + 2];
	double f[polynomial_order + 2];//

	double v[number_of_points + 1];
	double d[number_of_points + 1];
	double e[number_of_points + 1];//
	double x[number_of_points + 1];
	double y[number_of_points + 1];

	int l;//
	int n = number_of_points;//
	int m = polynomial_order;//

	double e1 = 0.0;//
	double dd;
	double vv;

  //Labels: e10,e15,e20,e30,e50,fin;
  int i;
  int l2;
  int n1; //

  double a1;//
  double a2;
  double b1;
  double b2;
  double c1;//
  double d1;//
  double f1;//
  double f2;
  double v1; //
  double v2;
  double w;//

  l = 0;
  n1 = m + 1;
  v1 = 1e7;

  for (i = 0; i < number_of_points; i++)
  {
	  x[i + 1] = data_x[i];

	  wxPrintf("Before %i = %f\n", i, data_y[i]);
	  y[i + 1] = data_y[i];
  }

  // Initialize the arrays
  for (i = 1; i < n1+1; i++) {
    a[i] = 0; b[i] = 0; f[i] = 0;
  };
  for (i = 1; i < n+1; i++) {
    v[i] = 0; d[i] = 0;
  }
  d1 = sqrt(n); w = d1;
  for (i = 1; i < n+1; i++) {
    e[i] = 1 / w;
  }
  f1 = d1; a1 = 0;
  for (i = 1; i < n+1; i++) {
    a1 = a1 + x[i] * e[i] * e[i];
  }
  c1 = 0;
  for (i = 1; i < n+1; i++) {
    c1 = c1 + y[i] * e[i];
  }
  b[1] = 1 / f1; f[1] = b[1] * c1;
  for (i = 1; i < n+1; i++) {
    v[i] = v[i] + e[i] * c1;
  }
  m = 1;
e10: // Save latest results
  for (i = 1; i < l+1; i++)  c2[i] = c[i];
  l2 = l; v2 = v1; f2 = f1; a2 = a1; f1 = 0;
  for (i = 1; i < n+1; i++) {
    b1 = e[i];
    e[i] = (x[i] - a2) * e[i] - f2 * d[i];
    d[i] = b1;
    f1 = f1 + e[i] * e[i];
  }
  f1 = sqrt(f1);
  for (i = 1; i < n+1; i++)  e[i] = e[i] / f1;
  a1 = 0;
  for (i = 1; i < n+1; i++)  a1 = a1 + x[i] * e[i] * e[i];
  c1 = 0;
  for (i = 1; i < n+1; i++)  c1 = c1 + e[i] * y[i];
  m = m + 1; i = 0;
e15: l = m - i; b2 = b[l]; d1 = 0;
  if (l > 1)  d1 = b[l - 1];
  d1 = d1 - a2 * b[l] - f2 * a[l];
  b[l] = d1 / f1; a[l] = b2; i = i + 1;
  if (i != m) goto e15;
  for (i = 1; i < n+1; i++)  v[i] = v[i] + e[i] * c1;
  for (i = 1; i < n1+1; i++) {
    f[i] = f[i] + b[i] * c1;
    c[i] = f[i];
  }
  vv = 0;
  for (i = 1; i < n+1; i++)
	  vv = vv + (v[i] - y[i]) * (v[i] - y[i]);
  //Note the division is by the number of degrees of freedom
  vv = sqrt(vv / (n - l - 1)); l = m;
  if (e1 == 0) goto e20;
  //Test for minimal improvement
  if (fabs(v1 - vv) / vv < e1) goto e50;
  //if error is larger, quit
  if (e1 * vv > e1 * v1) goto e50;
  v1 = vv;
e20: if (m == n1) goto e30;
  goto e10;
e30: //Shift the c[i] down, so c(0) is the constant term
  for (i = 1; i < l+1; i++)  c[i - 1] = c[i];
  c[l] = 0;
  //l is the order of the polynomial fitted
  l = l - 1; dd = vv;
  goto fin;
e50: // Aborted sequence, recover last values
  l = l2; vv = v2;
  for (i = 1; i < l+1; i++)  c[i] = c2[i];
  goto e30;
fin: ;

for (i = 0; i < number_of_points; i++)
{
	polynomial_fit[i] = v[i + 1];
	wxPrintf("After %i = %f\n", i, polynomial_fit[i]);
}

for (i = 0; i < polynomial_order; i++)
{
	polynomial_coefficients[i] = c[i + 1];
}

}
*/
void LS_POLY(float *x_data, float *y_data, int number_of_points, int order_of_polynomial, float *output_smoothed_curve, float *output_coefficients)
{

	double a[order_of_polynomial + 2];
	double b[order_of_polynomial + 2];
	double c[order_of_polynomial + 3];
	double c2[order_of_polynomial + 2];
	double f[order_of_polynomial + 2];

	double v[number_of_points + 1];
	double d[number_of_points + 1];
	double e[number_of_points + 1];
	double x[number_of_points + 1];
	double y[number_of_points + 1];

	int l;//
	int n = number_of_points;
	int m = order_of_polynomial;

	double e1 = 0.0;//
	double dd;
	double vv;

  //Labels: e10,e15,e20,e30,e50,fin;
	int i;
	int l2;
	int n1;

	double a1;
	double a2;
	double b1;
	double b2;
	double c1;
	double d1;
	double f1;
	double f2;
	double v1;
	double v2;
	double w;

	l = 0;
	n1 = m + 1;
	v1 = 1e7;

	for (i = 0; i < number_of_points; i++)
	{
		x[i + 1] = x_data[i];
		y[i + 1] = y_data[i];

		//wxPrintf("Before %i = %f\n", i, y_data[i]);

  }

  // Initialize the arrays
  for (i = 1; i < n1+1; i++) {
    a[i] = 0; b[i] = 0; f[i] = 0;
  };
  for (i = 1; i < n+1; i++) {
    v[i] = 0; d[i] = 0;
  }
  d1 = sqrt(n); w = d1;
  for (i = 1; i < n+1; i++) {
    e[i] = 1 / w;
  }
  f1 = d1; a1 = 0;
  for (i = 1; i < n+1; i++) {
    a1 = a1 + x[i] * e[i] * e[i];
  }
  c1 = 0;
  for (i = 1; i < n+1; i++) {
    c1 = c1 + y[i] * e[i];
  }
  b[1] = 1 / f1; f[1] = b[1] * c1;
  for (i = 1; i < n+1; i++) {
    v[i] = v[i] + e[i] * c1;
  }
  m = 1;
e10: // Save latest results
  for (i = 1; i < l+1; i++)  c2[i] = c[i];
  l2 = l; v2 = v1; f2 = f1; a2 = a1; f1 = 0;
  for (i = 1; i < n+1; i++) {
    b1 = e[i];
    e[i] = (x[i] - a2) * e[i] - f2 * d[i];
    d[i] = b1;
    f1 = f1 + e[i] * e[i];
  }
  f1 = sqrt(f1);
  for (i = 1; i < n+1; i++)  e[i] = e[i] / f1;
  a1 = 0;
  for (i = 1; i < n+1; i++)  a1 = a1 + x[i] * e[i] * e[i];
  c1 = 0;
  for (i = 1; i < n+1; i++)  c1 = c1 + e[i] * y[i];
  m = m + 1; i = 0;
e15: l = m - i; b2 = b[l]; d1 = 0;
  if (l > 1)  d1 = b[l - 1];
  d1 = d1 - a2 * b[l] - f2 * a[l];
  b[l] = d1 / f1; a[l] = b2; i = i + 1;
  if (i != m) goto e15;
  for (i = 1; i < n+1; i++)  v[i] = v[i] + e[i] * c1;
  for (i = 1; i < n1+1; i++) {
    f[i] = f[i] + b[i] * c1;
    c[i] = f[i];
  }
  vv = 0;
  for (i = 1; i < n+1; i++)
	  vv = vv + (v[i] - y[i]) * (v[i] - y[i]);
  //Note the division is by the number of degrees of freedom
  vv = sqrt(vv / (n - l - 1)); l = m;
  if (e1 == 0) goto e20;
  //Test for minimal improvement
  if (fabs(v1 - vv) / vv < e1) goto e50;
  //if error is larger, quit
  if (e1 * vv > e1 * v1) goto e50;
  v1 = vv;
e20: if (m == n1) goto e30;
  goto e10;
e30: //Shift the c[i] down, so c(0) is the constant term
  for (i = 1; i < l+1; i++)  c[i - 1] = c[i];
  c[l] = 0;
  //l is the order of the polynomial fitted
  l = l - 1; dd = vv;
  goto fin;
e50: // Aborted sequence, recover last values
  l = l2; vv = v2;
  for (i = 1; i < l+1; i++)  c[i] = c2[i];
  goto e30;
fin: ;

for (i = 0; i < number_of_points; i++)
{
	output_smoothed_curve[i] = v[i + 1];
//	output_smoothed_curve[i] = y[i + 1];
	//wxPrintf("After %i = %f\n", i, output_smoothed_curve[i]);
}

for (i = 0; i < order_of_polynomial; i++)
{
	output_coefficients[i] = c[i + 1];
}

}



