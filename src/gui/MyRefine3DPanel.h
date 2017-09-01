#ifndef __MyRefine3DPanel__
#define __MyRefine3DPanel__

/**
@file
Subclass of Refine3DPanel, which is generated by wxFormBuilder.
*/

#include "ProjectX_gui.h"

class MyRefine3DPanel;

class RefinementManager
{
public:
	bool start_with_reconstruction;
	MyRefine3DPanel *my_parent;

	float active_low_resolution_limit;
	float active_high_resolution_limit;
	float active_mask_radius;
	float active_signed_cc_limit;
	float active_global_mask_radius;
	int active_number_results_to_refine;
	float active_angular_search_step;
	float active_search_range_x;
	float active_search_range_y;
	float active_classification_high_res_limit;
	bool active_should_focus_classify;
	float active_sphere_x_coord;
	float active_sphere_y_coord;
	float active_sphere_z_coord;
	bool active_should_refine_ctf;
	float active_defocus_search_range;
	float active_defocus_search_step;
	float active_percent_used;
	float active_inner_mask_radius;
	float active_resolution_limit_rec;
	float active_score_weight_conversion;
	float active_score_threshold;
	bool active_adjust_scores;
	bool active_crop_images;
	bool active_should_apply_blurring;
	float active_smoothing_factor;
	float active_sphere_radius;
	bool active_do_global_refinement;
	bool active_also_refine_input;
	bool active_should_refine_psi;
	bool active_should_refine_theta;
	bool active_should_refine_phi;
	bool active_should_refine_x_shift;
	bool active_should_refine_y_shift;
	bool active_should_mask;
	bool active_should_auto_mask;
	wxString active_mask_filename;
	bool active_should_low_pass_filter_mask;
	float active_mask_filter_resolution;
	float active_mask_edge;
	float active_mask_weight;

	long current_job_starttime;
	long time_of_last_update;
	int number_of_generated_3ds;

	int running_job_type;
	int number_of_rounds_to_run;
	int number_of_rounds_run;
	long current_job_id;

	long current_refinement_package_asset_id;
	long current_input_refinement_id;
	long current_output_refinement_id;

	long number_of_received_particle_results;

	RefinementPackage *active_refinement_package;
	Refinement *input_refinement;
	Refinement *output_refinement;

	RunProfile active_refinement_run_profile;
	RunProfile active_reconstruction_run_profile;

	wxArrayString current_reference_filenames;
	wxArrayLong current_reference_asset_ids;

	void SetParent(MyRefine3DPanel *wanted_parent);

	void BeginRefinementCycle();
	void CycleRefinement();

	void SetupRefinementJob();
	void SetupReconstructionJob();
	void SetupMerge3dJob();

	void SetupInitialReconstructionJob();
	void SetupInitialMerge3dJob();

	void RunInitialReconstructionJob();
	void RunInitialMerge3dJob();

	void RunRefinementJob();
	void RunReconstructionJob();
	void RunMerge3dJob();

	void ProcessJobResult(JobResult *result_to_process);
	void ProcessAllJobsFinished();

	void OnMaskerThreadComplete();

	void DoMasking();

//	void StartRefinement();
//	void StartReconstruction();


};


class MyRefine3DPanel : public Refine3DPanel
{
	friend class RefinementManager;

	protected:
		// Handlers for Refine3DPanel events.
		void OnUpdateUI( wxUpdateUIEvent& event );
		void OnExpertOptionsToggle( wxCommandEvent& event );
		void OnInfoURL( wxTextUrlEvent& event );
		void TerminateButtonClick( wxCommandEvent& event );
		void FinishButtonClick( wxCommandEvent& event );
		void StartRefinementClick( wxCommandEvent& event );
		void ResetAllDefaultsClick( wxCommandEvent& event );
		void OnHighResLimitChange( wxCommandEvent& event );

		void OnUseMaskCheckBox( wxCommandEvent& event );
		void OnAutoMaskButton( wxCommandEvent& event );

		void OnVolumeListItemActivated( wxListEvent& event );
		void OnJobSocketEvent(wxSocketEvent& event);

		int length_of_process_number;

		RefinementManager my_refinement_manager;

	public:


		long time_of_last_result_update;

		bool refinement_package_combo_is_dirty;
		bool run_profiles_are_dirty;
		bool input_params_combo_is_dirty;
		bool volumes_are_dirty;

		JobResult *buffered_results;
		long my_job_id;
		long selected_refinement_package;

		//int length_of_process_number;

		JobPackage my_job_package;
		JobTracker my_job_tracker;

		bool auto_mask_value; // this is needed to keep track of the automask, as the radiobutton will be overidden to no when masking is selected

		bool running_job;

		void SetDefaults();


		MyRefine3DPanel( wxWindow* parent );
		void SetInfo();

		void WriteInfoText(wxString text_to_write);
		void WriteErrorText(wxString text_to_write);
		void WriteBlueText(wxString text_to_write);

		void FillRefinementPackagesComboBox();
		void FillRunProfileComboBoxes();
		void FillInputParamsComboBox();
		void ReDrawActiveReferences();

		void NewRefinementPackageSelected();

		void OnRefinementPackageComboBox( wxCommandEvent& event );
		void OnInputParametersComboBox( wxCommandEvent& event );

		void OnOrthThreadComplete(MyOrthDrawEvent& my_event);
		void OnMaskerThreadComplete(wxThreadEvent& my_event);
};

class Refine3DMaskerThread : public wxThread
{
	public:
	Refine3DMaskerThread(Refine3DPanel *parent, wxArrayString wanted_input_files, wxArrayString wanted_output_files, wxString wanted_mask_filename, float wanted_cosine_edge_width, float wanted_weight_outside_mask, float wanted_low_pass_filter_radius, float wanted_pixel_size) : wxThread(wxTHREAD_DETACHED)
	{
		main_thread_pointer = parent;
		input_files = wanted_input_files;
		output_files = wanted_output_files;
		mask_filename = wanted_mask_filename;
		cosine_edge_width = wanted_cosine_edge_width;
		weight_outside_mask = wanted_weight_outside_mask;
		low_pass_filter_radius = wanted_low_pass_filter_radius;
		pixel_size = wanted_pixel_size;
	}

	protected:

	Refine3DPanel *main_thread_pointer;
	wxArrayString input_files;
	wxArrayString output_files;
	wxString mask_filename;

	float cosine_edge_width;
	float weight_outside_mask;
	float low_pass_filter_radius;
	float pixel_size;

    virtual ExitCode Entry();
};


#endif // __MyRefine3DPanel__
