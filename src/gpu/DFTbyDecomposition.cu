/*
 * DFTbyDecomposition.cpp
 *
 *  Created on: Oct 21, 2020
 *      Author: himesb
 */

#include "gpu_core_headers.h"

#include "/groups/himesb/cufftdx/include/cufftdx.hpp"
// block_io depends on fp16. Both included from version () on 2020 Oct 30 as IO here may break on future changes

#include "fp16_common.hpp"
#include "block_io.hpp"

//#include "block_io.hpp"

//#include "/groups/himesb/cufftdx/example/common.hpp"

using namespace cufftdx;

const int test_size = 4096;
// Elements per thread must be [2,32]
const int ept = 16;
// FFts per block. Might be able to re-use twiddles but prob more mem intensive. TODO test me and also evaluate memory size
const int ffts_per_block = 1; // 1 is the default, higher numbers don't work yet. Might be to do with padding. FIXME

__global__ void DFT_R2C_WithPaddingKernel(cufftReal* input_values, cufftComplex* output_values, int4 dims_in, int4 dims_out, float C);
__global__ void DFT_C2C_WithPaddingKernel_strided(cufftComplex* input_values, int4 dims_in, int4 dims_out, float C);
__global__ void DFT_R2C_WithPaddingKernel_strided(cufftReal* input_values, cufftComplex* output_values, int4 dims_in, int4 dims_out, float C);
__global__ void DFT_C2C_WithPaddingKernel(cufftComplex* input_values, int4 dims_in, int4 dims_out, float C);
__global__ void DFT_C2C_WithPaddingKernel_rdx2(cufftComplex* input_values, int4 dims_in, int4 dims_out, float C);

template<class FFT>
__global__ void block_fft_kernel_R2C(typename FFT::input_type* input_values, typename FFT::output_type* output_values, int4 dims_in, int4 dims_out, float twid_constant, int n_sectors);

template<class FFT>
__global__ void block_fft_kernel_R2C_strided(typename FFT::input_type* input_values, typename FFT::output_type* output_values, int4 dims_in, int4 dims_out, float twid_constant, int n_sectors);

template<class FFT>
__global__ void block_fft_kernel_C2C_strided(typename FFT::input_type* input_values, typename FFT::output_type* output_values, int4 dims_in, int4 dims_out, float twid_constant, int n_sectors);

template<class FFT>
//__launch_bounds__(FFT::max_threads_per_block) __global__
__global__ void block_fft_kernel_C2C(typename FFT::input_type* input_values, typename FFT::output_type* output_values, int4 dims_in, int4 dims_out, float twid_constant, int n_sectors);


template<class FFT, class ComplexType = typename FFT::value_type, class ScalarType = typename ComplexType::value_type>
__launch_bounds__(FFT::max_threads_per_block) __global__
void block_fft_kernel_R2C_rotate(ScalarType* input_values, ComplexType* output_values, int4 dims_in, int4 dims_out, typename FFT::workspace_type workspace, bool rotate);

//template<class FFT>
//__global__ void block_fft_kernel_R2C_rotate(float* input_values, typename FFT::output_type* output_values, int4 dims_in, int4 dims_out, typename FFT::workspace_type workspace);
template<class FFT, class ComplexType = typename FFT::value_type>
__launch_bounds__(FFT::max_threads_per_block) __global__
void block_fft_kernel_C2C_rotate(ComplexType* input_values, ComplexType* output_values, int4 dims_in, int4 dims_out, typename FFT::workspace_type workspace, bool rotate);

template<class FFT, class ComplexType = typename FFT::value_type, class ScalarType = typename ComplexType::value_type>
__launch_bounds__(FFT::max_threads_per_block) __global__
void block_fft_kernel_C2R_rotate(ComplexType* input_values, ScalarType* output_values, int4 dims_in, int4 dims_out, typename FFT::workspace_type workspace, bool rotate);


using FFT_256          = decltype(Block() + Size<256>() + Type<fft_type::c2c>() +
                     Precision<float>() + ElementsPerThread<2>() + FFTsPerBlock<1>() + SM<700>());
using FFT_16          = decltype(Block() + Size<16>() + Type<fft_type::c2c>() +
                     Precision<float>() + ElementsPerThread<2>() + FFTsPerBlock<1>() + SM<700>());
using FFT_4096_r2c   = decltype(Block() + Size<test_size>() + Type<fft_type::r2c>() +
                     Precision<float>() + ElementsPerThread<ept>() + FFTsPerBlock<ffts_per_block>() + SM<700>());
using FFT_4096_c2c   = decltype(Block() + Size<test_size>() + Type<fft_type::c2c>() +
                     Precision<float>() + ElementsPerThread<ept>() + FFTsPerBlock<ffts_per_block>() + SM<700>());
using FFT_4096_c2r   = decltype(Block() + Size<test_size>() + Type<fft_type::c2r>() +
                     Precision<float>() + ElementsPerThread<ept>() + FFTsPerBlock<ffts_per_block>() + SM<700>());

DFTbyDecomposition::DFTbyDecomposition() // @suppress("Class members should be properly initialized")
{
	is_set_gpu_images = false;
	is_set_twiddles = false;
	is_allocated_rotated_buffer = false;
//	is_set_outputs = false;
}

DFTbyDecomposition::~DFTbyDecomposition()
{
	if (is_set_twiddles)
	{
		cudaErr(cudaFree(twiddles));
	}
	if (is_allocated_rotated_buffer)
	{
		cudaErr(cudaFree(d_rotated_buffer));

	}
//	if (is_set_outputs)
//	{
//		cudaErr(cudaFree(output_real));
//		cudaErr(cudaFree(output_imag));
//	}
}

DFTbyDecomposition::DFTbyDecomposition(const DFTbyDecomposition &other)
{
	// TODO Auto-generated constructor stub

}

DFTbyDecomposition& DFTbyDecomposition::operator=(
		const DFTbyDecomposition &other) {
	// TODO Auto-generated method stub

}

void DFTbyDecomposition::InitTestCase(int wanted_input_size_x, int wanted_input_size_y, int wanted_output_size_x, int wanted_output_size_y)
{
	dims_input = make_int2(wanted_input_size_x, wanted_input_size_y);
	dims_output = make_int2(wanted_output_size_x, wanted_output_size_y);

	// In practice we'll give a pointer to the arrays in some GpuImages
}

void DFTbyDecomposition::SetGpuImages(Image& cpu_input, Image& cpu_output)
{

	// Should be in real space, TODO add check
	input_image.CopyFromCpuImage(cpu_input);
	input_image.CopyHostToDevice();

	if (&cpu_output != &cpu_input)
	{
		wxPrintf("Initializing output image\n");
		// Initialize to Fourier space
		output_image.CopyFromCpuImage(cpu_output);
		output_image.CopyHostToDevice();

//		output_image.Allocate((int)dims_output.x, (int)dims_output.y, 1, false);
//		output_image.Zeros();
	}
	else
	{
		output_image = input_image;
	}

	wxPrintf("Sizes in init %d %d in and %d %d out\n",input_image.dims.x, input_image.dims.y, output_image.dims.x, output_image.dims.y);

	is_set_gpu_images = true;

}

void DFTbyDecomposition::AllocateRotatedBuffer()
{
	MyAssertTrue(is_set_gpu_images,"Gpu images must be set before allocating a buffer");

	cudaErr(cudaMalloc(&d_rotated_buffer, sizeof(float)*output_image.real_memory_allocated));

	is_allocated_rotated_buffer = true;
}


void DFTbyDecomposition::DFT_R2C_WithPadding()
{

	// FIXME when adding real space complex images
	MyAssertTrue( input_image.is_in_memory_gpu, "Input image is in not on the GPU!");
	MyAssertTrue( output_image.is_in_memory_gpu, "Output image is in not on the GPU!");



	int threadsPerBlock = input_image.dims.x; // FIXME make sure its a multiple of 32
	int gridDims = input_image.dims.y;
//	dim3 gridDims = dim3((output_image.dims.w/2 + threadsPerBlock - 1) / threadsPerBlock,
//					  	1, 1);
//  output_image.dims.y
	int shared_mem = sizeof(float)*input_image.dims.x;
	float C = -2*PIf/output_image.dims.x;
	DFT_R2C_WithPaddingKernel<< <gridDims, threadsPerBlock, shared_mem, cudaStreamPerThread>> > ( input_image.real_values_gpu,  output_image.complex_values_gpu, input_image.dims, output_image.dims, C);
	cudaStreamSynchronize(cudaStreamPerThread);



}

__global__ void DFT_R2C_WithPaddingKernel(cufftReal* input_values, cufftComplex* output_values, int4 dims_in, int4 dims_out, float C)
{

//	// Initialize the shared memory, assuming everying matches the input data X size in
	extern __shared__ float s[];
	// Avoid N*k type conversion and multiplication
	float* data = s;
//	float* coeff= (float*)&data[dims_in.x];


	int x = threadIdx.x;
	int pixel_out = (dims_out.w/2)*blockIdx.x;


	data[x] = __ldg((const float *)&input_values[dims_in.w*blockIdx.x + x]);
	__syncthreads();
//
//	 Loop over N updating the actual twiddle value along the way. This might lead to accuracy problems.
	float sum_real;
	float sum_imag;
	float twi_r;
	float twi_i;
	float coeff;

	for (int k = threadIdx.x; k < dims_out.w/2; k+=blockDim.x)
	{
		coeff = C*(float)k;
		sum_real = 0.0f;
		sum_imag = 0.0f;
		for (int n = 0; n < dims_in.x; n++)
		{
			__sincosf(coeff*n,&twi_i,&twi_r);
			sum_real = __fmaf_rn(data[n],twi_r,sum_real);
			sum_imag = __fmaf_rn(data[n],twi_i,sum_imag);
		}

		// Not sure if an async write, or storage to a shared mem temp would be faster.
		output_values[pixel_out + k].x = sum_real;
		output_values[pixel_out + k].y = sum_imag;
	}


	return;

}


void DFTbyDecomposition::DFT_C2C_WithPadding()
{

	// FIXME when adding real space complex images
	MyAssertTrue( input_image.is_in_memory_gpu, "Input image is in not on the GPU!");
	MyAssertTrue( output_image.is_in_memory_gpu, "Output image is in not on the GPU!");


	int threadsPerBlock = input_image.dims.x; // FIXME make sure its a multiple of 32
	int gridDims = output_image.dims.w/2;

	int shared_mem = sizeof(cufftComplex)*input_image.dims.x;

	float C = -2*PIf/output_image.dims.x;
	DFT_C2C_WithPaddingKernel<< <gridDims, threadsPerBlock, shared_mem, cudaStreamPerThread>> > ( output_image.complex_values_gpu, input_image.dims, output_image.dims, C);
	cudaStreamSynchronize(cudaStreamPerThread);



}

__global__ void DFT_C2C_WithPaddingKernel(cufftComplex* inplace_image, int4 dims_in, int4 dims_out, float C)
{

	// Initialize the shared memory, assuming everying matches the input data X size in
	// Check that setting cudaFuncSetSharedMemConfig  to 8byte makes any diff for complex reads
	extern __shared__ cufftComplex c[];
	cufftComplex* data = c;


	int x = threadIdx.x;
	int pixel_out = (dims_out.w/2)*blockIdx.x;

	data[x] = __ldg((const cufftComplex *)&inplace_image[pixel_out + x]);
	__syncthreads();
//
//	 Loop over N updating the actual twiddle value along the way. This might lead to accuracy problems.
	cufftComplex sum;
	float twi_r;
	float twi_i;
	float coeff;
	float tmp;

	for (int k = threadIdx.x; k < dims_out.w/2; k+=blockDim.x)
	{
		coeff = C*(float)k;
		sum.x = 0.0f;
		sum.y = 0.0f;
		for (int n = 0; n < dims_in.y; n++)
		{
			__sincosf(coeff*n,&twi_i,&twi_r);
			tmp = data[n].x * twi_i;
			sum.x += __fmaf_rn(data[n].x, twi_r, -twi_i * data[n].y);
			sum.y += __fmaf_rn(data[n].y, twi_r, tmp);
		}

		// Not sure if an async write, or storage to a shared mem temp would be faster.
//		inplace_image[pixel_out + k].x = sum_real;
//		inplace_image[pixel_out + k].y = sum_imag;
		inplace_image[pixel_out + k] = sum;
	}



	return;

}


void DFTbyDecomposition::DFT_R2C_WithPadding_strided()
{

	// FIXME when adding real space complex images
	MyAssertTrue( input_image.is_in_memory_gpu, "Input image is in not on the GPU!");
	MyAssertTrue( output_image.is_in_memory_gpu, "Output image is in not on the GPU!");



	int threadsPerBlock = input_image.dims.y; // FIXME make sure its a multiple of 32
	int gridDims = input_image.dims.x;
//	dim3 gridDims = dim3((output_image.dims.w/2 + threadsPerBlock - 1) / threadsPerBlock,
//					  	1, 1);
//  output_image.dims.y
	int shared_mem = sizeof(float)*input_image.dims.y;
	float C = -2*PIf/output_image.dims.y;
	DFT_R2C_WithPaddingKernel_strided<< <gridDims, threadsPerBlock, shared_mem, cudaStreamPerThread>> > ( input_image.real_values_gpu,  output_image.complex_values_gpu, input_image.dims, output_image.dims, C);
	cudaStreamSynchronize(cudaStreamPerThread);



}

__global__ void DFT_R2C_WithPaddingKernel_strided(cufftReal* input_values, cufftComplex* output_values, int4 dims_in, int4 dims_out, float C)
{

//	// Initialize the shared memory, assuming everying matches the input data X size in
	extern __shared__ float s[];
	// Avoid N*k type conversion and multiplication
	float* data = s;
//	float* coeff= (float*)&data[dims_in.x];


	int y = threadIdx.x;
	int pixel_in = blockIdx.x + y * (dims_in.w);

	data[y] = __ldg((const cufftReal *)&input_values[pixel_in]);
	__syncthreads();
//

//
//	 Loop over N updating the actual twiddle value along the way. This might lead to accuracy problems.
	float sum_real;
	float sum_imag;
	float twi_r;
	float twi_i;
	float coeff;

	for (int k = threadIdx.x; k < dims_out.y; k+=blockDim.x)
	{
		coeff = C*(float)k;
		sum_real = 0.0f;
		sum_imag = 0.0f;
		for (int n = 0; n < dims_in.x; n++)
		{
			__sincosf(coeff*n,&twi_i,&twi_r);
			sum_real = __fmaf_rn(data[n],twi_r,sum_real);
			sum_imag = __fmaf_rn(data[n],twi_i,sum_imag);
		}

		// Not sure if an async write, or storage to a shared mem temp would be faster.
		// Not sure if an async write, or storage to a shared mem temp would be faster.
		output_values[blockIdx.x + k * (dims_out.w/2)].x = sum_real;
		output_values[blockIdx.x + k * (dims_out.w/2)].y = sum_imag;
	}


	return;

}


void DFTbyDecomposition::DFT_C2C_WithPadding_strided()
{

	// FIXME when adding real space complex images
	MyAssertTrue( input_image.is_in_memory_gpu, "Input image is in not on the GPU!");
	MyAssertTrue( output_image.is_in_memory_gpu, "Output image is in not on the GPU!");


	int threadsPerBlock = input_image.dims.y; // FIXME make sure its a multiple of 32
	int gridDims = output_image.dims.w/2;

	int shared_mem = sizeof(cufftComplex)*input_image.dims.y;

	float C = -2*PIf/output_image.dims.y;
	DFT_C2C_WithPaddingKernel_strided<< <gridDims, threadsPerBlock, shared_mem, cudaStreamPerThread>> > ( output_image.complex_values_gpu, input_image.dims, output_image.dims, C);
	cudaStreamSynchronize(cudaStreamPerThread);



}

__global__ void DFT_C2C_WithPaddingKernel_strided(cufftComplex* inplace_image, int4 dims_in, int4 dims_out, float C)
{

	// Initialize the shared memory, assuming everying matches the input data X size in
	// Check that setting cudaFuncSetSharedMemConfig  to 8byte makes any diff for complex reads
	extern __shared__ cufftComplex c[];
	cufftComplex* data = c;


	int y = threadIdx.x;
	int pixel_in = blockIdx.x + y * (dims_out.w/2);


	data[y] = __ldg((const cufftComplex *)&inplace_image[pixel_in]);
	__syncthreads();
//
//	 Loop over N updating the actual twiddle value along the way. This might lead to accuracy problems.
	float sum_real;
	float sum_imag;
	float twi_r;
	float twi_i;
	float coeff;
	float tmp;

	for (int k = threadIdx.x; k < dims_out.y; k+=blockDim.x)
	{
		coeff = C*(float)k;
		sum_real = 0.0f;
		sum_imag = 0.0f;
		for (int n = 0; n < dims_in.y; n++)
		{
			__sincosf(coeff*n,&twi_i,&twi_r);
			tmp = data[n].x * twi_i;
			sum_real += __fmaf_rn(data[n].x, twi_r, -twi_i * data[n].y);
			sum_imag += __fmaf_rn(data[n].y, twi_r, tmp);
		}

		// Not sure if an async write, or storage to a shared mem temp would be faster.
		inplace_image[blockIdx.x + k * (dims_out.w/2)].x = sum_real;
		inplace_image[blockIdx.x + k * (dims_out.w/2)].y = sum_imag;
	}


	return;

}

void DFTbyDecomposition::DFT_C2C_WithPadding_rdx2()
{

	// FIXME when adding real space complex images
	MyAssertTrue( input_image.is_in_memory_gpu, "Input image is in not on the GPU!");
	MyAssertTrue( output_image.is_in_memory_gpu, "Output image is in not on the GPU!");


	int threadsPerBlock = input_image.dims.x; // FIXME make sure its a multiple of 32
	int gridDims = output_image.dims.w/2;

	int shared_mem = sizeof(cufftComplex)*input_image.dims.x;

	float C = -2*PIf/output_image.dims.x*2;
	DFT_C2C_WithPaddingKernel_rdx2<< <gridDims, threadsPerBlock, shared_mem, cudaStreamPerThread>> > ( output_image.complex_values_gpu, input_image.dims, output_image.dims, C);
	cudaStreamSynchronize(cudaStreamPerThread);



}

__global__ void DFT_C2C_WithPaddingKernel_rdx2(cufftComplex* inplace_image, int4 dims_in, int4 dims_out, float C)
{

	// Initialize the shared memory, assuming everying matches the input data X size in
	// Check that setting cudaFuncSetSharedMemConfig  to 8byte makes any diff for complex reads
	extern __shared__ cufftComplex c[];
	cufftComplex* data = c;


	int x = threadIdx.x;
	int pixel_out = (dims_out.w/2)*blockIdx.x;

	data[x] = __ldg((const cufftComplex *)&inplace_image[pixel_out + x]);
	__syncthreads();
//
//	 Loop over N updating the actual twiddle value along the way. This might lead to accuracy problems.
	cufftComplex sum;
	cufftComplex eve;
	float twi_r;
	float twi_i;
	float coeff;
	float tmp;

	for (int k = threadIdx.x; k < dims_out.w/4; k+=blockDim.x)
	{
		// get the even DFT
		coeff = C*(float)k;
		sum.x = 0.0f;
		sum.y = 0.0f;
		for (int n = 0; n < dims_in.y; n+=2)
		{
			__sincosf(coeff*n,&twi_i,&twi_r);
			tmp = data[n].x * twi_i;
			sum.x += __fmaf_rn(data[n].x, twi_r, -twi_i * data[n].y);
			sum.y += __fmaf_rn(data[n].y, twi_r, tmp);
		}

		eve = sum;

		// get the odd DFT
		sum.x = 0.0f;
		sum.y = 0.0f;
		for (int n = 1; n < dims_in.y; n+=2)
		{
			__sincosf(coeff*n,&twi_i,&twi_r);
			tmp = data[n].x * twi_i;
			sum.x += __fmaf_rn(data[n].x, twi_r, -twi_i * data[n].y);
			sum.y += __fmaf_rn(data[n].y, twi_r, tmp);
		}

		// Get the twiddle for the combined radix
		__sincosf(coeff/2.0f,&twi_i,&twi_r);
		// Multiply the odd
		tmp = sum.x * twi_i;
		sum.x = __fmaf_rn(sum.x, twi_r, -twi_i * sum.y);
		sum.y = __fmaf_rn(sum.y, twi_r, tmp);

		inplace_image[pixel_out + k].x = eve.x + sum.x;
		inplace_image[pixel_out + k].y = eve.y + sum.y;

		inplace_image[pixel_out + k + dims_out.w/4].x = eve.x - sum.x;
		inplace_image[pixel_out + k + dims_out.w/4].y = eve.y - sum.y;

	}



	return;

}


void DFTbyDecomposition::FFT_R2C_WithPadding_strided()
{

	// This is the first set of 1d ffts when the input data are real valued, accessing the strided dimension. Since we need the full length, it will actually run a C2C xform

	// FIXME when adding real space complex images
	MyAssertTrue( input_image.is_in_memory_gpu, "Input image is in not on the GPU!");
	MyAssertTrue( output_image.is_in_memory_gpu, "Output image is in not on the GPU!");

	// Elements per thread must be [2,32]
    const int ept = 2;

    // FFts per block. Might be able to re-use twiddles but prob more mem intensive. TODO test me and also evaluate memory size
    const int ffts_per_block = 1; // 1 is the default.

    // For now consider the simplest launch params, where one input element is handled per thread.
    MyAssertFalse(input_image.dims.y % ept, "The elements per thread is not a divisor of the input y-dimension.");
	int threadsPerBlock = input_image.dims.y / ept; // FIXME make sure its a multiple of 32
	int gridDims = input_image.dims.x;

	// For the twiddle factors ahead of the P size ffts
	float CN = -2*PIf/output_image.dims.y;
	int   IQ = output_image.dims.y / input_image.dims.y; // FIXME assuming for now this is already divisible

    // FFT is defined, its: size, type, direction, precision. Block() operator informs that FFT
    // will be executed on block level. Shared memory is required for co-operation between threads.


	if (input_image.dims.y == 256)
	{
	    using FFT = decltype(FFT_256() + Direction<fft_direction::forward>() );
		int shared_mem = sizeof(FFT::value_type)*(input_image.dims.y) + FFT::shared_memory_size*8;
		block_fft_kernel_R2C_strided<FFT><< <gridDims, threadsPerBlock, shared_mem, cudaStreamPerThread>> > ( (typename FFT::input_type*)input_image.real_values_gpu,  (typename FFT::output_type*)output_image.complex_values_gpu, input_image.dims, output_image.dims, CN,IQ);



	}
	else if (input_image.dims.y == 16)
	{
	    using FFT = decltype(FFT_16() + Direction<fft_direction::forward>() );
		int shared_mem = sizeof(float)*(2+input_image.dims.y) + FFT::shared_memory_size*8;
		block_fft_kernel_R2C_strided<FFT><< <gridDims, threadsPerBlock, shared_mem, cudaStreamPerThread>> > ( (typename FFT::input_type*)input_image.real_values_gpu,  (typename FFT::output_type*)output_image.complex_values_gpu, input_image.dims, output_image.dims, CN,IQ);


	}
	else
	{
		exit(-1);
	}




}

template<class FFT>
//__launch_bounds__(FFT::max_threads_per_block) __global__
__global__ void block_fft_kernel_R2C_strided(typename FFT::input_type* input_values, typename FFT::output_type* output_values, int4 dims_in, int4 dims_out, float twid_constant, int n_sectors)
{

//	// Initialize the shared memory, assuming everying matches the input data X size in
    using complex_type = typename FFT::value_type;

	extern __shared__  complex_type real_data[];
	complex_type* shared_mem_work  = (complex_type*)&real_data[dims_in.y];
	float* fake_input = reinterpret_cast<float*>(input_values);


	// Memory used by FFT
	complex_type twiddle;
    complex_type thread_data[FFT::storage_size];

    // To re-map the thread index to the data
    int input_MAP[FFT::storage_size];
    // To re-map the decomposed frequency to the full output frequency
    int output_MAP[FFT::storage_size];
    // For a given decomposed fragment
    float twiddle_factors_args[FFT::storage_size];

    // This way reads are
    int i;

    for (i = 0; i < FFT::elements_per_thread; i++)
    {
    	// index into the input data
    	input_MAP[i] = threadIdx.x + i * (size_of<FFT>::value / FFT::elements_per_thread);
		output_MAP[i] = n_sectors * input_MAP[i];
		twiddle_factors_args[i] = twid_constant * input_MAP[i];

		// Unpack the floats and move from shared mem into the register space.in R2C this would happen anyway as a preprocessing step.
		real_data[input_MAP[i]].x = __ldg((const cufftReal *)&fake_input[blockIdx.x + input_MAP[i] * (dims_in.w)]);
		real_data[input_MAP[i]].y = 0.0f;
    }
	__syncthreads();


	// this data will be re-used for each n_sectors FFTs
    for (i = 0; i < FFT::elements_per_thread; i++)
    {
		thread_data[i] = real_data[input_MAP[i]];
    }


    // For loop zero the twiddles don't need to be computed
    FFT().execute(thread_data, shared_mem_work);

    // The memory access is strided anyway so just send to global
    for (i = 0; i < FFT::elements_per_thread; i++)
    {
        output_values[blockIdx.x + output_MAP[i] * (dims_out.w/2)] = thread_data[i];
    }

    // For the other fragments we need the initial twiddle
	for (int fft_fragment = 1; fft_fragment < n_sectors; fft_fragment++)
	{
	    for (i = 0; i < FFT::elements_per_thread; i++)
	    {
			// Pre shift with twiddle
			__sincosf(twiddle_factors_args[i]*fft_fragment,&twiddle.y,&twiddle.x);
			twiddle *= real_data[input_MAP[i]]; // Only the inplace operators are included in cufftdx::types TODO expand
		    thread_data[i] = twiddle;
	    }

	      FFT().execute(thread_data, shared_mem_work);

		for (i = 0; i < FFT::elements_per_thread; i++)
		{
		      output_values[blockIdx.x + (fft_fragment + output_MAP[i]) * (dims_out.w/2)] = thread_data[i];
		}

	}



	return;

}

void DFTbyDecomposition::FFT_R2C_WithPadding()
{

	// This is the first set of 1d ffts when the input data are real valued, accessing the strided dimension. Since we need the full length, it will actually run a C2C xform

	// FIXME when adding real space complex images
	MyAssertTrue( input_image.is_in_memory_gpu, "Input image is in not on the GPU!");
	MyAssertTrue( output_image.is_in_memory_gpu, "Output image is in not on the GPU!");

	// Elements per thread must be [2,32]
    const int ept = 2;

    // FFts per block. Might be able to re-use twiddles but prob more mem intensive. TODO test me and also evaluate memory size
    const int ffts_per_block = 1; // 1 is the default.

    // For now consider the simplest launch params, where one input element is handled per thread.
    MyAssertFalse(input_image.dims.x % ept, "The elements per thread is not a divisor of the input y-dimension.");
	int threadsPerBlock = input_image.dims.x / ept; // FIXME make sure its a multiple of 32
	int gridDims = input_image.dims.y;

	// For the twiddle factors ahead of the P size ffts
	float CN = -2*PIf/output_image.dims.x;
	int   IQ = output_image.dims.x / input_image.dims.x; // FIXME assuming for now this is already divisible
    // FFT is defined, its: size, type, direction, precision. Block() operator informs that FFT
    // will be executed on block level. Shared memory is required for co-operation between threads.


	if (input_image.dims.y == 256)
	{
	    using FFT = decltype(FFT_256() + Direction<fft_direction::forward>() );
		int shared_mem = sizeof(FFT::output_type)*(input_image.dims.x) + FFT::shared_memory_size*8;
		block_fft_kernel_R2C<FFT><< <gridDims, threadsPerBlock, shared_mem, cudaStreamPerThread>> > ( (typename FFT::input_type*)input_image.real_values_gpu,  (typename FFT::output_type*)output_image.complex_values_gpu, input_image.dims, output_image.dims, CN,IQ);



	}
	else if (input_image.dims.y == 16)
	{
	    using FFT = decltype(FFT_16() + Direction<fft_direction::forward>() );
		int shared_mem = sizeof(FFT::value_type)*(input_image.dims.x) + FFT::shared_memory_size*8;
		block_fft_kernel_R2C<FFT><< <gridDims, threadsPerBlock, shared_mem, cudaStreamPerThread>> > ( (typename FFT::input_type*)input_image.real_values_gpu,  (typename FFT::output_type*)output_image.complex_values_gpu, input_image.dims, output_image.dims, CN,IQ);

	}
	else
	{
		exit(-1);
	}




}

template<class FFT>
//__launch_bounds__(FFT::max_threads_per_block) __global__
__global__ void block_fft_kernel_R2C(typename FFT::input_type* input_values, typename FFT::output_type* output_values, int4 dims_in, int4 dims_out, float twid_constant, int n_sectors)
{

//	// Initialize the shared memory, assuming everying matches the input data X size in
    using complex_type = typename FFT::value_type;

	extern __shared__  complex_type shared_mem_work[];
	complex_type* real_data = (complex_type*)&shared_mem_work[FFT::shared_memory_size];
	float* fake_input = reinterpret_cast<float*>(input_values);

	// Memory used by FFT
	complex_type twiddle;
    complex_type thread_data[FFT::storage_size];

    // To re-map the thread index to the data
    int input_MAP[FFT::storage_size];
    // To re-map the decomposed frequency to the full output frequency
    int output_MAP[FFT::storage_size];
    // For a given decomposed fragment
    float twiddle_factors_args[FFT::storage_size];

    // This way reads are
    int i;

    for (i = 0; i < FFT::elements_per_thread; i++)
    {
    	// index into the input data
    	input_MAP[i] = threadIdx.x + i * (size_of<FFT>::value / FFT::elements_per_thread);
		output_MAP[i] = n_sectors * input_MAP[i];
		twiddle_factors_args[i] = twid_constant * input_MAP[i];

		// Unpack the floats and move from shared mem into the register space.in R2C this would happen anyway as a preprocessing step.
		real_data[input_MAP[i]].x = __ldg((const cufftReal *)&fake_input[blockIdx.x * dims_in.w + input_MAP[i]]);
		real_data[input_MAP[i]].y = 0.0f;
    }
	__syncthreads();


	// this data will be re-used for each n_sectors FFTs
    for (i = 0; i < FFT::elements_per_thread; i++)
    {
		thread_data[i] = real_data[input_MAP[i]];
    }


    // For loop zero the twiddles don't need to be computed
    FFT().execute(thread_data, shared_mem_work);



	// The memory access is strided anyway so just send to global
	for (i = 0; i < FFT::elements_per_thread; i++)
	{
		if (output_MAP[i] < dims_out.w/2) // FIXME we should just do a R2C normal here
		{
			output_values[blockIdx.x  * (dims_out.w/2) + output_MAP[i]] = thread_data[i];
		}
	}


    // For the other fragments we need the initial twiddle
	for (int fft_fragment = 1; fft_fragment < n_sectors; fft_fragment++)
	{
	    for (i = 0; i < FFT::elements_per_thread; i++)
	    {
			// Pre shift with twiddle
			__sincosf(twiddle_factors_args[i]*fft_fragment,&twiddle.y,&twiddle.x);
			twiddle *= real_data[input_MAP[i]]; // Only the inplace operators are included in cufftdx::types TODO expand
		    thread_data[i] = twiddle;
	    }

	      FFT().execute(thread_data, shared_mem_work);

		for (i = 0; i < FFT::elements_per_thread; i++)
		{
		    if ((fft_fragment + output_MAP[i]) < dims_out.w/2) // FIXME we should just do a R2C normal here
		    {
		      output_values[blockIdx.x  * (dims_out.w/2) + (fft_fragment + output_MAP[i])] = thread_data[i];
		    }
		}

	}



	return;

}

void DFTbyDecomposition::FFT_C2C_WithPadding_strided()
{

	// This is the first set of 1d ffts when the input data are real valued, accessing the strided dimension. Since we need the full length, it will actually run a C2C xform

	// FIXME when adding real space complex images
	MyAssertTrue( input_image.is_in_memory_gpu, "Input image is in not on the GPU!");
	MyAssertTrue( output_image.is_in_memory_gpu, "Output image is in not on the GPU!");

	// Elements per thread must be [2,32]
    const int ept = 2;

    // FFts per block. Might be able to re-use twiddles but prob more mem intensive. TODO test me and also evaluate memory size
    const int ffts_per_block = 1; // 1 is the default.

    // For now consider the simplest launch params, where one input element is handled per thread.
    MyAssertFalse(input_image.dims.y % ept, "The elements per thread is not a divisor of the input y-dimension.");
	int threadsPerBlock = input_image.dims.y / ept; // FIXME make sure its a multiple of 32
	int gridDims = output_image.dims.w/2;

	// For the twiddle factors ahead of the P size ffts
	float CN = -2*PIf/output_image.dims.y;
	int   IQ = output_image.dims.y / input_image.dims.y; // FIXME assuming for now this is already divisible

    // FFT is defined, its: size, type, direction, precision. Block() operator informs that FFT
    // will be executed on block level. Shared memory is required for co-operation between threads.


	if (input_image.dims.y == 256)
	{
	    using FFT = decltype(FFT_256() + Direction<fft_direction::forward>() );
		int shared_mem = sizeof(FFT::value_type)*(input_image.dims.y) + FFT::shared_memory_size*8;
		block_fft_kernel_C2C_strided<FFT><< <gridDims, threadsPerBlock, shared_mem, cudaStreamPerThread>> > ( (typename FFT::input_type*)output_image.complex_values_gpu,  (typename FFT::output_type*)output_image.complex_values_gpu, input_image.dims, output_image.dims, CN,IQ);


	}
	else if (input_image.dims.y == 16)
	{
	    using FFT = decltype(FFT_16() + Direction<fft_direction::forward>() );
		int shared_mem = sizeof(float)*(input_image.dims.y) + FFT::shared_memory_size*8;
		block_fft_kernel_C2C_strided<FFT><< <gridDims, threadsPerBlock, shared_mem, cudaStreamPerThread>> > ( (typename FFT::input_type*)output_image.complex_values_gpu,  (typename FFT::output_type*)output_image.complex_values_gpu, input_image.dims, output_image.dims, CN,IQ);
		output_image.printVal("out 1",0);
		output_image.printVal("out 1",1);

		output_image.printVal("out 1",2);
		output_image.printVal("out 1",3);
		output_image.printVal("out 1",4);
		output_image.printVal("out 1",5);



	}
	else
	{
		exit(-1);
	}




}

template<class FFT>
//__launch_bounds__(FFT::max_threads_per_block) __global__
__global__ void block_fft_kernel_C2C_strided(typename FFT::input_type* input_values, typename FFT::output_type* output_values, int4 dims_in, int4 dims_out, float twid_constant, int n_sectors)
{

//	// Initialize the shared memory, assuming everying matches the input data X size in
    using complex_type = typename FFT::value_type;

	extern __shared__  complex_type real_data[];
	complex_type* shared_mem_work_3= (complex_type*)&real_data[dims_in.y];


	// Memory used by FFT
	complex_type twiddle;
    complex_type thread_data[FFT::elements_per_thread];

    // To re-map the thread index to the data
    int input_MAP[FFT::elements_per_thread];
    // To re-map the decomposed frequency to the full output frequency
    int output_MAP[FFT::elements_per_thread];
    // For a given decomposed fragment
    float twiddle_factors_args[FFT::elements_per_thread];

    // This way reads are
    int i;

    for (i = 0; i < FFT::elements_per_thread; i++)
    {
    	// index into the input data
    	input_MAP[i] = threadIdx.x + i * (size_of<FFT>::value / FFT::elements_per_thread);
		output_MAP[i] = n_sectors * input_MAP[i];
		twiddle_factors_args[i] = twid_constant * input_MAP[i];

		// Unpack the floats and move from shared mem into the register space.in R2C this would happen anyway as a preprocessing step.
		real_data[input_MAP[i]].x = __ldg((const float*)&input_values[blockIdx.x + input_MAP[i] * (dims_out.w/2)].x);
		real_data[input_MAP[i]].y = __ldg((const float*)&input_values[blockIdx.x + input_MAP[i] * (dims_out.w/2)].y);

    }
	__syncthreads();


	// this data will be re-used for each n_sectors FFTs
    for (i = 0; i < FFT::elements_per_thread; i++)
    {
		thread_data[i] = real_data[input_MAP[i]];
    }


    // For loop zero the twiddles don't need to be computed
    FFT().execute(thread_data, shared_mem_work_3);

    // The memory access is strided anyway so just send to global
    for (i = 0; i < FFT::elements_per_thread; i++)
    {
        output_values[blockIdx.x + output_MAP[i] * (dims_out.w/2)] = thread_data[i];
    }

    // For the other fragments we need the initial twiddle
	for (int fft_fragment = 1; fft_fragment < n_sectors; fft_fragment++)
	{
	    for (i = 0; i < FFT::elements_per_thread; i++)
	    {
			// Pre shift with twiddle
			__sincosf(twiddle_factors_args[i]*fft_fragment,&twiddle.y,&twiddle.x);
			twiddle *= real_data[input_MAP[i]]; // Only the inplace operators are included in cufftdx::types TODO expand
		    thread_data[i] = twiddle;
	    }

	      FFT().execute(thread_data, shared_mem_work_3);

		for (i = 0; i < FFT::elements_per_thread; i++)
		{
		      output_values[blockIdx.x + (fft_fragment + output_MAP[i]) * (dims_out.w/2)] = thread_data[i];
		}

	}



	return;

}

void DFTbyDecomposition::FFT_C2C_WithPadding()
{

	// This is the first set of 1d ffts when the input data are real valued, accessing the strided dimension. Since we need the full length, it will actually run a C2C xform

	// FIXME when adding real space complex images
	MyAssertTrue( input_image.is_in_memory_gpu, "Input image is in not on the GPU!");
	MyAssertTrue( output_image.is_in_memory_gpu, "Output image is in not on the GPU!");

	// Elements per thread must be [2,32]
    const int ept = 2;

    // FFts per block. Might be able to re-use twiddles but prob more mem intensive. TODO test me and also evaluate memory size
    const int ffts_per_block = 1; // 1 is the default.

    // For now consider the simplest launch params, where one input element is handled per thread.
    MyAssertFalse(input_image.dims.x % ept, "The elements per thread is not a divisor of the input y-dimension.");
	int threadsPerBlock = input_image.dims.x / ept; // FIXME make sure its a multiple of 32
	int gridDims = output_image.dims.y;

	// For the twiddle factors ahead of the P size ffts
	float CN = -2*PIf/output_image.dims.x;
	int   IQ = output_image.dims.x / input_image.dims.x; // FIXME assuming for now this is already divisible
    // FFT is defined, its: size, type, direction, precision. Block() operator informs that FFT
    // will be executed on block level. Shared memory is required for co-operation between threads.


	if (input_image.dims.y == 256)
	{
	    using FFT = decltype(FFT_256() + Direction<fft_direction::forward>() );
		int shared_mem = sizeof(FFT::output_type)*(input_image.dims.x) + FFT::shared_memory_size*8;
		block_fft_kernel_C2C<FFT><< <gridDims, threadsPerBlock, shared_mem, cudaStreamPerThread>> > ( (typename FFT::input_type*)input_image.real_values_gpu,  (typename FFT::output_type*)output_image.complex_values_gpu, input_image.dims, output_image.dims, CN,IQ);



	}
	else if (input_image.dims.y == 16)
	{
	    using FFT = decltype(FFT_16() + Direction<fft_direction::forward>() );
		int shared_mem = sizeof(FFT::value_type)*(input_image.dims.x) + FFT::shared_memory_size*8;
		block_fft_kernel_R2C<FFT><< <gridDims, threadsPerBlock, shared_mem, cudaStreamPerThread>> > ( (typename FFT::input_type*)input_image.real_values_gpu,  (typename FFT::output_type*)output_image.complex_values_gpu, input_image.dims, output_image.dims, CN,IQ);

	}
	else
	{
		exit(-1);
	}




}

template<class FFT>
//__launch_bounds__(FFT::max_threads_per_block) __global__
__global__ void block_fft_kernel_C2C(typename FFT::input_type* input_values, typename FFT::output_type* output_values, int4 dims_in, int4 dims_out, float twid_constant, int n_sectors)
{

//	// Initialize the shared memory, assuming everying matches the input data X size in
    using complex_type = typename FFT::value_type;

	extern __shared__  complex_type real_data[];
	complex_type* shared_mem_work = (complex_type*)&real_data[dims_in.x];

	// Memory used by FFT
	complex_type twiddle;
    complex_type thread_data[FFT::storage_size];

    // To re-map the thread index to the data
    int input_MAP[FFT::storage_size];

    // To re-map the decomposed frequency to the full output frequency
    int output_MAP[FFT::storage_size];
    // For a given decomposed fragment
    float twiddle_factors_args[FFT::storage_size];

    // This way reads are
    int i;

    for (i = 0; i < FFT::elements_per_thread; i++)
    {
    	// index into the input data
    	input_MAP[i] = threadIdx.x + i * (size_of<FFT>::value / FFT::elements_per_thread);
		output_MAP[i] = n_sectors * input_MAP[i];
		twiddle_factors_args[i] = twid_constant * input_MAP[i];

		// Unpack the floats and move from shared mem into the register space.in R2C this would happen anyway as a preprocessing step.
		real_data[input_MAP[i]].x = __ldg((const cufftReal *)&output_values[blockIdx.x * dims_in.w/2 + input_MAP[i]].x);
		real_data[input_MAP[i]].y = __ldg((const cufftReal *)&output_values[blockIdx.x * dims_in.w/2 + input_MAP[i]].y);
    }
	__syncthreads();


	// this data will be re-used for each n_sectors FFTs
    for (i = 0; i < FFT::elements_per_thread; i++)
    {
		thread_data[i] = real_data[input_MAP[i]];
    }


    // For loop zero the twiddles don't need to be computed
    FFT().execute(thread_data, shared_mem_work);



	// The memory access is strided anyway so just send to global
	for (i = 0; i < FFT::elements_per_thread; i++)
	{
		if (output_MAP[i] < dims_out.w/2) // FIXME we should just do a R2C normal here
		{
			output_values[blockIdx.x  * (dims_out.w/2) + output_MAP[i]] = thread_data[i];
		}
	}


    // For the other fragments we need the initial twiddle
	for (int fft_fragment = 1; fft_fragment < n_sectors; fft_fragment++)
	{
	    for (i = 0; i < FFT::elements_per_thread; i++)
	    {
			// Pre shift with twiddle
			__sincosf(twiddle_factors_args[i]*fft_fragment,&twiddle.y,&twiddle.x);
			twiddle *= real_data[input_MAP[i]]; // Only the inplace operators are included in cufftdx::types TODO expand
		    thread_data[i] = twiddle;
	    }

	      FFT().execute(thread_data, shared_mem_work);

		for (i = 0; i < FFT::elements_per_thread; i++)
		{
		    if ((fft_fragment + output_MAP[i]) < dims_out.w/2) // FIXME we should just do a R2C normal here
		    {
		      output_values[blockIdx.x  * (dims_out.w/2) + (fft_fragment + output_MAP[i])] = thread_data[i];
		    }
		}

	}



	return;

}

void DFTbyDecomposition::FFT_R2C_rotate(bool rotate)
{

	// This is the first set of 1d ffts when the input data are real valued, accessing the strided dimension. Since we need the full length, it will actually run a C2C xform

	// FIXME when adding real space complex images
	MyAssertTrue( input_image.is_in_memory_gpu, "Input image is in not on the GPU!");
	MyAssertTrue( is_allocated_rotated_buffer, "Output image is in not on the GPU!");


	dim3 threadsPerBlock = dim3(test_size/ept, 1, 1); // FIXME make sure its a multiple of 32
	// NY R2C Transforms of size NX
	dim3 gridDims = dim3(1,1,(input_image.dims.y + ffts_per_block - 1)/ffts_per_block);

	using FFT = decltype( FFT_4096_r2c() + Direction<fft_direction::forward>() );
//	wxPrintf("FFT::block_dim %d %d %d\n", FFT::block_dim.x,FFT::block_dim.y,FFT::block_dim.z );
	using complex_type = typename FFT::value_type;
	using scalar_type    = typename complex_type::value_type;

//	wxPrintf("In R2C the advised EPT (%d) and ffts per block (%d)\n",FFT::elements_per_thread,FFT::suggested_ffts_per_block);

//    for (int i=0+4094; i < 5+4094; i++)
//    {
//    	input_image.printVal("val",i);
//    }
//    for (int i=4090+4094; i < 4098+4094; i++)
//    {
//    	input_image.printVal("val",i);
//    }
	cudaError_t error_code = cudaSuccess;
	auto workspace = make_workspace<FFT>(error_code);
	block_fft_kernel_R2C_rotate<FFT,complex_type,scalar_type><< <gridDims,  FFT::block_dim, FFT::shared_memory_size, cudaStreamPerThread>> >
	( (scalar_type *)input_image.real_values_gpu,  (complex_type*)d_rotated_buffer, input_image.dims, output_image.dims, workspace, rotate);

//	cudaErr(cudaPeekAtLastError());
//	cudaErr(cudaDeviceSynchronize());


}

template<class FFT, class ComplexType, class ScalarType>
__launch_bounds__(FFT::max_threads_per_block) __global__
void block_fft_kernel_R2C_rotate(ScalarType* input_values, ComplexType* output_values, int4 dims_in, int4 dims_out, typename FFT::workspace_type workspace, bool rotate)
{

	// FIXME using exact sizes so every thread and every block is included. Need overflow checks
	if (ffts_per_block*blockIdx.z > dims_in.y-ffts_per_block) return;
//	// Initialize the shared memory, assuming everyting matches the input data X size in
    using complex_type = ComplexType;
    using scalar_type  = ScalarType;

	extern __shared__  complex_type shared_mem[];
    complex_type thread_data[FFT::storage_size];


    constexpr int stride = size_of<FFT>::value / FFT::elements_per_thread;
    int index = threadIdx.x;

    bah_io::io<FFT>::load_r2c(&input_values[ffts_per_block*blockIdx.z * dims_in.w], thread_data, dims_in.w*threadIdx.y);

//    for (int i = 0; i < FFT::elements_per_thread; i++)
//    {
//    	reinterpret_cast<scalar_type*>(thread_data)[i] = __ldg((const float*)&input_values[blockIdx.x * dims_in.w + index]);
//    	index += stride;
//    }


    FFT().execute(thread_data, shared_mem, workspace);

    // index gives us x in the unrotated line, and blockIdx.x*dims_in.w gives us y
    // x' is = y, and y' = dims_in.w/2 - x - 1

    if (rotate)
    {
        index = threadIdx.x;
        for (int i = 0; i < FFT::elements_per_thread / 2 ; i++)
        {
        	//
        	if (rotate) output_values[blockIdx.z + (dims_out.w/2 - index - 1)*dims_out.y] = thread_data[i];
        	// Y * NX + X
        	else output_values[blockIdx.z * dims_out.w/2 + index] = thread_data[i];

        	index += stride;
        }

        constexpr unsigned int threads_per_fft        = cufftdx::size_of<FFT>::value / FFT::elements_per_thread;
        constexpr unsigned int output_values_to_store = (cufftdx::size_of<FFT>::value / 2) + 1;
        // threads_per_fft == 1 means that EPT == SIZE, so we need to store one more element
        constexpr unsigned int values_left_to_store =
            threads_per_fft == 1 ? 1 : (output_values_to_store % threads_per_fft);
        if (threadIdx.x < values_left_to_store)
        {
        	output_values[blockIdx.z + (dims_out.w/2 - index - 1)*dims_out.y] =  thread_data[FFT::elements_per_thread / 2];
        }


    }
    else
    {
        bah_io::io<FFT>::store_r2c(thread_data, &output_values[ffts_per_block*blockIdx.z * dims_in.w/2], dims_out.w/2*threadIdx.y);
    }

	return;

}

void DFTbyDecomposition::FFT_C2C_rotate(bool rotate, bool forward_transform)
{

	// This is the first set of 1d ffts when the input data are real valued, accessing the strided dimension. Since we need the full length, it will actually run a C2C xform

	// FIXME when adding real space complex images
	MyAssertTrue( is_allocated_rotated_buffer, "Input image is in not on the GPU!");
	MyAssertTrue( output_image.is_in_memory_gpu, "Output Image is not on the GPU");

	dim3 threadsPerBlock = dim3(test_size/ept,1,1);
	// The rotated image now has size NY x NW/2
	dim3 gridDims = dim3(1,1,(output_image.dims.w/2+ffts_per_block-1)/ffts_per_block);



		if (forward_transform)
		{
		    using FFT = decltype(FFT_4096_c2c() + Direction<fft_direction::forward>() );
		    cudaError_t error_code = cudaSuccess;
		    auto workspace = make_workspace<FFT>(error_code);
		    using complex_type = typename FFT::value_type;

		    // On the forward the input is in the buffer, do an out of place transform and put back into the roiginal memory
			block_fft_kernel_C2C_rotate<FFT, complex_type><< <gridDims, FFT::block_dim, FFT::shared_memory_size, cudaStreamPerThread>> >
			( (complex_type*)d_rotated_buffer, (complex_type*)output_image.complex_values_gpu, input_image.dims, output_image.dims, workspace, rotate);
//		    cudaErr(cudaPeekAtLastError());
//		    cudaErr(cudaDeviceSynchronize());


		}
		else
		{
		    using FFT = decltype(FFT_4096_c2c() + Direction<fft_direction::inverse>() );
		    cudaError_t error_code = cudaSuccess;
		    auto workspace = make_workspace<FFT>(error_code);
		    using complex_type = typename FFT::value_type;

			// On the inverse, do out of place and put back into the bufffer
			block_fft_kernel_C2C_rotate<FFT, complex_type><< <gridDims,  FFT::block_dim, FFT::shared_memory_size, cudaStreamPerThread>> >
			( (complex_type*)output_image.complex_values_gpu, (complex_type*)d_rotated_buffer, input_image.dims, output_image.dims, workspace, rotate);
//		    cudaErr(cudaPeekAtLastError());
//		    cudaErr(cudaDeviceSynchronize());


		}




}

template<class FFT, class ComplexType>
__launch_bounds__(FFT::max_threads_per_block) __global__
void block_fft_kernel_C2C_rotate(ComplexType* input_values, ComplexType* output_values, int4 dims_in, int4 dims_out, typename FFT::workspace_type workspace, bool rotate)
{

	// FIXME using exact sizes so every thread and every block is included. Need overflow checks
	if (ffts_per_block*blockIdx.z > dims_out.w/2-ffts_per_block) return;
//	// Initialize the shared memory, assuming everyting matches the input data X size in
    using complex_type = ComplexType;

	extern __shared__  complex_type shared_mem[];

    complex_type thread_data[FFT::storage_size];
    int source_idx[FFT::storage_size];
    constexpr int stride = size_of<FFT>::value / FFT::elements_per_thread;
    int index = threadIdx.x;

    if (rotate)
    {
        for (int i = 0; i < FFT::elements_per_thread; i++)
        {
        	thread_data[i] = __ldg((const double*)&input_values[blockIdx.x*dims_out.y + index]);
        	index += stride;
        }
    }
    else
    {
        bah_io::io<FFT>::load(&input_values[ffts_per_block*blockIdx.z], thread_data, source_idx, dims_out.w/2, (int)threadIdx.y);

    }




    FFT().execute(thread_data, shared_mem, workspace);

    if (rotate)
    {
		index = threadIdx.x;
		for (int i = 0; i < FFT::elements_per_thread; i++)
		{
			output_values[blockIdx.x*dims_out.y + index] = thread_data[i];
			index += stride;
		}
    }
    else
    {
        bah_io::io<FFT>::store(thread_data, &output_values[ffts_per_block*blockIdx.z], source_idx, dims_out.w/2);
    }


	return;

}

void DFTbyDecomposition::FFT_C2R_rotate(bool rotate)
{

	// This is the first set of 1d ffts when the input data are real valued, accessing the strided dimension. Since we need the full length, it will actually run a C2C xform

	// FIXME when adding real space complex images
	MyAssertTrue( is_allocated_rotated_buffer, "Input image is in not on the GPU!");
	MyAssertTrue( input_image.is_in_memory_gpu, "Output image is in not on the GPU!");

	// Elements per thread must be [2,32]

	dim3 threadsPerBlock = dim3(test_size/ept,1,1); // FIXME make sure its a multiple of 32
	dim3 gridDims = dim3(1,1,(output_image.dims.y+ffts_per_block-1)/ffts_per_block);


	using FFT = decltype(FFT_4096_c2r() + Direction<fft_direction::inverse>() );
	cudaError_t error_code = cudaSuccess;
	auto workspace = make_workspace<FFT>(error_code);
	using complex_type = typename FFT::value_type;
	using scalar_type    = typename complex_type::value_type;

	// On the inverse, do out of place and put back into the bufffer
	block_fft_kernel_C2R_rotate<FFT, complex_type, scalar_type><< <gridDims,  FFT::block_dim, FFT::shared_memory_size, cudaStreamPerThread>> >
	( (complex_type*)d_rotated_buffer, (scalar_type*)output_image.real_values_gpu, input_image.dims, output_image.dims, workspace, rotate);
//	cudaErr(cudaPeekAtLastError());
//	cudaErr(cudaDeviceSynchronize());
//
//	output_image.MultiplyByConstant(1/4096);
//	cudaErr(cudaPeekAtLastError());
//	cudaErr(cudaDeviceSynchronize());
//    for (int i=0+4094; i < 5+4094; i++)
//    {
//    	output_image.printVal("val out",i);
//    }
//    for (int i=4090+4094; i < 4098+4094; i++)
//    {
//    	output_image.printVal("val out",i);
//    }



}

template<class FFT, class ComplexType, class ScalarType>
__launch_bounds__(FFT::max_threads_per_block) __global__
void block_fft_kernel_C2R_rotate(ComplexType* input_values, ScalarType* output_values, int4 dims_in, int4 dims_out, typename FFT::workspace_type workspace, bool rotate)
{

	// FIXME using exact sizes so every thread and every block is included. Need overflow checks
	if (ffts_per_block*blockIdx.z > dims_out.y - ffts_per_block) return;
//	// Initialize the shared memory, assuming everyting matches the input data X size in
	//	// Initialize the shared memory, assuming everyting matches the input data X size in
	using complex_type = ComplexType;
	using scalar_type  = ScalarType;

	extern __shared__  complex_type shared_mem[];


    complex_type thread_data[FFT::storage_size];
	int index = threadIdx.x;
	constexpr int half_idx = FFT::elements_per_thread / 2;
	constexpr int stride =  (size_of<FFT>::value / FFT::elements_per_thread);
    if (rotate)
    {


		// inputs are NY xforms of length NW/2, read in strided and rotate
		// blockIdx.x is Y in the rotated frame
		for (int i = 0; i < half_idx; i++)
		{
			if (rotate) thread_data[i] = __ldg((const double*)&input_values[blockIdx.z + dims_out.y * (dims_out.w/2 - index - 1)]);
			else thread_data[i] = __ldg((const double*)&input_values[blockIdx.z * dims_out.w/2 + index]);
			index += stride;
		}

		constexpr unsigned int threads_per_fft       = cufftdx::size_of<FFT>::value / FFT::elements_per_thread;
		constexpr unsigned int output_values_to_load = (cufftdx::size_of<FFT>::value / 2) + 1;
		// threads_per_fft == 1 means that EPT == SIZE, so we need to load one more element
		constexpr unsigned int values_left_to_load =
			threads_per_fft == 1 ? 1 : (output_values_to_load % threads_per_fft);
		if (threadIdx.x < values_left_to_load)
		{
			thread_data[half_idx] = __ldg((const double*)&input_values[blockIdx.z + dims_out.y * (dims_out.w/2 - index - 1)]);
//			else thread_data[half_idx] = __ldg((const double*)&input_values[blockIdx.z * dims_out.w/2 + index]);

		}
	}
    else
    {
        bah_io::io<FFT>::load_c2r(&input_values[ffts_per_block*blockIdx.z * dims_in.w/2], thread_data, dims_out.w/2*threadIdx.y);
    }
//	bah_io::io<FFT>::load(&input_values[blockIdx.z * dims_out.y], thread_data, 1);


    // For loop zero the twiddles don't need to be computed
    FFT().execute(thread_data, shared_mem, workspace);

    if (rotate)
    {
		index = threadIdx.x;
		for (int i = 0; i < FFT::elements_per_thread; i++)
			{
				output_values[index + blockIdx.z*dims_out.w] = reinterpret_cast<const scalar_type*>(thread_data)[i];
				index += stride;
			}
    }
    else
    {
        bah_io::io<FFT>::store_c2r(thread_data, &output_values[ffts_per_block*blockIdx.z * dims_in.w],dims_out.w * threadIdx.y);
    }

	return;

}


template<class FFT, class ComplexType = typename FFT::value_type, class ScalarType = typename ComplexType::value_type>
__launch_bounds__(FFT::max_threads_per_block) __global__
void block_fft_kernel_r2cT(ScalarType* input_data, ComplexType* output_data)
{

	// FIXME using exact sizes so every thread and every block is included. Need overflow checks
    using complex_type = ComplexType;
    using scalar_type = ScalarType;

    // Local array for thread
    complex_type thread_data[FFT::storage_size];


    int source_idx[FFT::storage_size];

        for (int i = 0; i < FFT::elements_per_thread; i++)
        {
        	source_idx[i] = threadIdx.x + i * (size_of<FFT>::value / FFT::elements_per_thread);
        	reinterpret_cast<scalar_type*>(thread_data)[i] = __ldg((const float*)&input_data[blockIdx.x * 4098 + source_idx[i]]);
        }

    // ID of FFT in CUDA block, in range [0; FFT::ffts_per_block)
    const unsigned int local_fft_id = threadIdx.y;
    // Load data from global memory to registers
//    example::io<FFT>::load_r2c(input_data, thread_data, local_fft_id);

    // Execute FFT
    extern __shared__ complex_type shared_mem[];
    FFT().execute(thread_data, shared_mem);

    // Save results
//    example::io<FFT>::store_r2c(thread_data, output_data, local_fft_id);
}

// In this example a one-dimensional real-to-complex transform is performed by a CUDA block.
//
// One block is run, it calculates two 128-point R2C float precision FFTs.
// Data is generated on host, copied to device buffer, and then results are copied back to host.
// Notice different sizes of input and output buffer, and R2C load and store operations in the kernel.
//template<unsigned int Arch>
int DFTbyDecomposition::test_main() {
    using namespace cufftdx;
    unsigned int Arch = 700;
    wxPrintf("in simple\n");
    // FFT is defined, its: size, type, direction, precision. Block() operator informs that FFT
    // will be executed on block level. Shared memory is required for co-operation between threads.
    using FFT          = decltype(Block() + Size<4096>() + Type<fft_type::r2c>() + Direction<fft_direction::forward>() +
                         Precision<float>() + ElementsPerThread<8>() + FFTsPerBlock<1>() + SM<700>());
    using complex_type = typename FFT::value_type;
    using real_type    = typename complex_type::value_type;

    // Allocate managed memory for input/output
    real_type* input_data;

    auto       input_size       =2* FFT::ffts_per_block * cufftdx::size_of<FFT>::value;
    auto       input_size_bytes = input_size * sizeof(real_type);

    float* cpu_input = new float[input_size];
    for (size_t i = 0; i < input_size; i++) {
    	cpu_input[i] = float(i);
    }

    cudaErr(cudaMalloc(&input_data, input_size_bytes));
    cudaErr(cudaMemcpy( input_data, cpu_input,input_size_bytes,cudaMemcpyHostToDevice));
//    cudaErr(cudaMallocManaged(&input_data, input_size_bytes));
//    for (size_t i = 0; i < input_size; i++) {
//        input_data[i] = float(i);
//    }
    MyPrintWithDetails("");
    complex_type* output_data;
    auto          output_size       = FFT::ffts_per_block * 2*(cufftdx::size_of<FFT>::value / 2 + 1);
    auto          output_size_bytes = output_size * sizeof(complex_type);
    cudaErr(cudaMallocManaged(&output_data, output_size_bytes));
    MyPrintWithDetails("");
//    std::cout << "input [1st FFT]:\n";
//    for (size_t i = 0; i < cufftdx::size_of<FFT>::value; i++) {
//        std::cout << input_data[i] << std::endl;
//    }
    std::cout << "Block dim" << FFT::block_dim.x << FFT::block_dim.y << FFT::block_dim.z << std::endl;
    MyPrintWithDetails("");
wxPrintf("Size of float %d  and size of real_typ%d\n",sizeof(float),sizeof(real_type));
    // Invokes kernel with FFT::block_dim threads in CUDA block
	real_type* dummy_ptr = reinterpret_cast<real_type*>(input_image.real_values_gpu);
//    block_fft_kernel_r2cT<FFT><<<2, FFT::block_dim, FFT::shared_memory_size>>>(input_data, output_data);
    block_fft_kernel_r2cT<FFT><<<2, FFT::block_dim, FFT::shared_memory_size>>>(dummy_ptr, output_data);

    cudaErr(cudaPeekAtLastError());
    cudaErr(cudaDeviceSynchronize());

    MyPrintWithDetails("");

    std::cout << "output [1st FFT]:\n";
    for (size_t i = 0; i < (cufftdx::size_of<FFT>::value / 2 + 1); i++) {
        std::cout << output_data[i].x << " " << output_data[i].y << std::endl;
        wxPrintf("%3.3f %3.3f\n",output_data[i].x,output_data[i].y);
    }
    MyPrintWithDetails("");

    std::cout << "arch" << Arch << std::endl;
    std::cout << "max threads" << FFT::max_threads_per_block << std::endl;
    cudaErr(cudaFree(input_data));
    cudaErr(cudaFree(output_data));
    std::cout << "Success" << std::endl;
}

//template<unsigned int Arch>
//struct simple_block_fft_r2c_functor {
//    void operator()() { return simple_block_fft_r2c<Arch>(); }
//};
//
//int DFTbyDecomposition::test_main()
//{
//	wxPrintf("In main\n");
//    return example::sm_runner<simple_block_fft_r2c_functor>();
//}

