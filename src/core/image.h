/*  \brief  Image class (derived from Fortran images module)

	for information on actual data management / addressing see the image_data_array class..

*/

class Image {


	int 		 logical_x_dimension;							// !< Logical (X) dimensions of the image., Note that this does not necessarily correspond to memory allocation dimensions (ie physical dimensions).
	int 		 logical_y_dimension;							// !< Logical (Y) dimensions of the image., Note that this does not necessarily correspond to memory allocation dimensions (ie physical dimensions).
	int 		 logical_z_dimension;							// !< Logical (Z) dimensions of the image., Note that this does not necessarily correspond to memory allocation dimensions (ie physical dimensions).

	bool 		 is_in_real_space;								// !< Whether the image is in real or Fourier space
	bool 		 object_is_centred_in_box;						//!<  Whether the object or region of interest is near the center of the box (as opposed to near the corners and wrapped around). This refers to real space and is meaningless in Fourier space.

	int			 physical_upper_bound_complex_x;				// !< In each dimension, the upper bound of the complex image's physical addresses
	int			 physical_upper_bound_complex_y;				// !< In each dimension, the upper bound of the complex image's physical addresses
	int			 physical_upper_bound_complex_z;				// !< In each dimension, the upper bound of the complex image's physical addresses

	int      	 physical_address_of_box_center_x;				// !< In each dimension, the address of the pixel at the origin
	int      	 physical_address_of_box_center_y;				// !< In each dimension, the address of the pixel at the origin
	int      	 physical_address_of_box_center_z;				// !< In each dimension, the address of the pixel at the origin

	int			 physical_index_of_first_negative_frequency_x;	// !<  In each dimension, the physical index of the first pixel which stores negative frequencies
	int			 physical_index_of_first_negative_frequency_y;	// !<  In each dimension, the physical index of the first pixel which stores negative frequencies
	int			 physical_index_of_first_negative_frequency_z;	// !<  In each dimension, the physical index of the first pixel which stores negative frequencies

	float  		 fourier_voxel_size_x;							// !<  Distance from Fourier voxel to Fourier voxel, expressed in reciprocal pixels
	float  		 fourier_voxel_size_y;							// !<  Distance from Fourier voxel to Fourier voxel, expressed in reciprocal pixels
	float  		 fourier_voxel_size_z;							// !<  Distance from Fourier voxel to Fourier voxel, expressed in reciprocal pixels

	int			 logical_upper_bound_complex_x;					// !<  In each dimension, the upper bound of the complex image's logical addresses
	int			 logical_upper_bound_complex_y;					// !<  In each dimension, the upper bound of the complex image's logical addresses
	int			 logical_upper_bound_complex_z;					// !<  In each dimension, the upper bound of the complex image's logical addresses

	int			 logical_lower_bound_complex_x;					// !<  In each dimension, the lower bound of the complex image's logical addresses
	int			 logical_lower_bound_complex_y;					// !<  In each dimension, the lower bound of the complex image's logical addresses
	int			 logical_lower_bound_complex_z;					// !<  In each dimension, the lower bound of the complex image's logical addresses

	int			 logical_upper_bound_real_x;					// !<  In each dimension, the upper bound of the real image's logical addresses
	int			 logical_upper_bound_real_y;					// !<  In each dimension, the upper bound of the real image's logical addresses
	int			 logical_upper_bound_real_z;					// !<  In each dimension, the upper bound of the real image's logical addresses

	int			 logical_lower_bound_real_x;					// !<  In each dimension, the lower bound of the real image's logical addresses
	int			 logical_lower_bound_real_y;					// !<  In each dimension, the lower bound of the real image's logical addresses
	int			 logical_lower_bound_real_z;					// !<  In each dimension, the lower bound of the real image's logical addresses

	long         real_memory_allocated;							// !<  Number of floats allocated in real space;


	// Arrays to hold voxel values

	float 	 	 *real_values;									// !<  Real array to hold values for REAL images.
	fftwf_complex *complex_values;								// !<  Complex array to hold values for COMP images.
	bool         is_in_memory;                                  // !<  Whether image values are in-memory, in other words whether the image has memory space allocated to its data array. Default = .FALSE.


	// FFTW-specfic

	fftwf_plan 	 plan_fwd;										// !< FFTW plan for the image (fwd)
	fftwf_plan	 plan_bwd;										// !< FFTW plan for the image (bwd)
	bool      	 planned;										// !< Whether the plan has been setup by/for FFTW

public:
	// Methods

	Image();
	~Image();

	void Allocate(int wanted_x_size, int wanted_y_size, int wanted_z_size = 1, bool is_in_real_space = true);
	void Allocate(int wanted_x_size, int wanted_y_size, bool is_in_real_space = true);
	void Deallocate();

	void SetLogicalDimensions(int wanted_x_size, int wanted_y_size, int wanted_z_size = 1);
	void UpdateLoopingAndAddressing();
	void UpdatePhysicalAddressOfBoxCenter();

	void DivideByConstant(float constant_to_divide_by);
	void MultiplyByConstant(float constant_to_multiply_by);

	void ForwardFFT(bool should_scale = true);
	void BackwardFFT();

	void AddFFTWPadding();
	void RemoveFFTWPadding();

	inline void ReadSlice(MRCFile *input_file, long slice_to_read) {ReadSlices(input_file, slice_to_read, slice_to_read);}; //!> \brief Read a a slice from disk..(this just calls ReadSlices)
	void ReadSlices(MRCFile *input_file, long start_slice, long end_slice);

	inline void WriteSlice(MRCFile *input_file, long slice_to_write) {WriteSlices(input_file, slice_to_write, slice_to_write);}
	void WriteSlices(MRCFile *input_file, long start_slice, long end_slice);


};


