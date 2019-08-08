#include "../../core/core_headers.h"
#include <wx/xml/xml.h>

class
WarpToCistemApp : public MyApp
{

	public:

	bool DoCalculation();
	MovieAsset LoadMovieFromWarp(wxXmlDocument warp_doc, wxString warp_folder, wxString movie_filename, unsigned long count, float wanted_binned_pixel_size);
	void DoInteractiveUserInput();

	wxString warp_directory;
	wxString cistem_parent_directory;
	wxString project_name;
	float wanted_binned_pixel_size;
	Project new_project;
	private:
};


IMPLEMENT_APP(WarpToCistemApp)

void WarpToCistemApp::DoInteractiveUserInput()
{
	wxString warp_directory = "";
	wxString cistem_parent_directory = "";
	wxString project_name = "";
	float wanted_binned_pixel_size = 1.0;
	UserInput *my_input = new UserInput("Warp to Cistem", 1.0);

	warp_directory = my_input->GetFilenameFromUser("Input Warp Directory", "The folder in which Warp processed movies", "./Data", false);
	cistem_parent_directory = my_input->GetFilenameFromUser("Cistem Project Parent Directory", "The parent directory for the new cistem project", "~/", false);
	project_name = my_input -> GetFilenameFromUser("Project Name", "Name for new cisTEM2 project", "New_Project", false);
	wanted_binned_pixel_size = my_input -> GetFloatFromUser("Binned Pixel Size", "Pixel size to resample movies to after import.", "1.0", 0.0);
	delete my_input;

	my_current_job.ManualSetArguments("tttf",	warp_directory.ToUTF8().data(), cistem_parent_directory.ToUTF8().data(), project_name.ToUTF8().data(), wanted_binned_pixel_size);

}

MovieAsset WarpToCistemApp::LoadMovieFromWarp(wxXmlDocument warp_doc, wxString warp_folder, wxString movie_filename, unsigned long count, float wanted_binned_pixel_size)
{
	MovieAsset new_asset = MovieAsset();
	new_asset.filename = movie_filename;
	new_asset.asset_name = new_asset.filename.GetName();
	new_asset.asset_id = count+1;
	new_asset.dark_filename = "";
	new_asset.output_binning_factor = 1.0;
	/* TODO: Replace this with logic to handle mag distortion info from Warp */
	new_asset.correct_mag_distortion = false;
	new_asset.mag_distortion_angle = 0.0;
	new_asset.mag_distortion_major_scale = 1.0;
	new_asset.mag_distortion_minor_scale = 1.0;
	wxString dimension_string = "";
	double pixel_size = 1.0;
	double cs = 2.7;
	double voltage=300;
	double dose_rate = 1.0;
	wxXmlNode *child_1 = warp_doc.GetRoot()->GetChildren();
	while (child_1) {
		if ((child_1)->GetName() == "OptionsCTF") {
			wxXmlNode *child_2 = child_1->GetChildren();
			while (child_2) {
				if (child_2->GetAttribute("Name") == "PixelSizeX") {
					wxString str_pixel_size = child_2->GetAttribute("Value");
					if(!str_pixel_size.ToDouble(&pixel_size)) {SendErrorAndCrash("Couldn't convert Pixel Size to a double");}
					new_asset.pixel_size = pixel_size;
					double binning_factor = wanted_binned_pixel_size/pixel_size;
					if (binning_factor >= 1.0) {
						new_asset.output_binning_factor = binning_factor;
					}
				}
				if (child_2->GetAttribute("Name") == "GainPath") {
					wxFileName gain_filename = wxFileName(child_2->GetAttribute("Value"), wxPATH_WIN);
					wxString adjusted_filename = warp_folder + gain_filename.GetFullName(); // This requires that the gain filename be in the warp folder! todo locate gain file more flexibly... user selected?
					new_asset.gain_filename = adjusted_filename;
				}
				if (child_2->GetAttribute("Name") == "Cs") {
					wxString str_cs = child_2->GetAttribute("Value");
					if(!str_cs.ToDouble(&cs)) {SendErrorAndCrash("Couldn't convert Spherical Aberration to a double");}
					new_asset.spherical_aberration = cs;
				}
				if (child_2->GetAttribute("Name") == "Voltage") {
					wxString str_voltage = child_2->GetAttribute("Value");
					if(!str_voltage.ToDouble(&voltage)) {SendErrorAndCrash("Couldn't convert Voltage to a double");}
					new_asset.microscope_voltage = voltage;
				}
				if (child_2->GetAttribute("Name") == "Dimensions") {
					dimension_string = child_2->GetAttribute("Value");
				}
				child_2 = child_2->GetNext();
			}
		}
		else if ((child_1)->GetName() == "OptionsMovieExport"){
			wxXmlNode *child_2 = child_1->GetChildren();
			while (child_2) {
				if (child_2->GetAttribute("Name") == "DosePerAngstromFrame") {
					wxString str_dose_rate = child_2->GetAttribute("Value");
					if(!str_dose_rate.ToDouble(&dose_rate)) {SendErrorAndCrash("Couldn't convert Dose Rate to a double");}
					new_asset.dose_per_frame = dose_rate;
				}
				child_2 = child_2->GetNext();
			}
		}
		child_1 = child_1->GetNext();
	}
	double x_size_angstroms = 0.0;
	double y_size_angstroms = 0.0;

	wxStringTokenizer tokenizer(dimension_string, ",");
	wxString str_x_size = tokenizer.GetNextToken();
	wxString str_y_size = tokenizer.GetNextToken();
	wxString str_number_of_frames = tokenizer.GetNextToken();
	if(!str_x_size.ToDouble(&x_size_angstroms)) {SendErrorAndCrash("Couldn't convert x size to a double");}
	int x_size = myroundint(x_size_angstroms/pixel_size);
	if(!str_y_size.ToDouble(&y_size_angstroms)) {SendErrorAndCrash("Couldn't convert y size to a double");}
	int y_size = myroundint(y_size_angstroms/pixel_size);
	int number_of_frames = wxAtoi(str_number_of_frames);
	new_asset.x_size = x_size;
	new_asset.y_size = y_size;
	new_asset.number_of_frames = number_of_frames;
	new_asset.total_dose = number_of_frames * new_asset.dose_per_frame;
	new_asset.protein_is_white = false;
	new_asset.is_valid = true;
	return new_asset;
}

bool WarpToCistemApp::DoCalculation()
{
	wxString warp_directory = my_current_job.arguments[0].ReturnStringArgument();
	wxString cistem_parent_directory = my_current_job.arguments[1].ReturnStringArgument();
	wxString project_name = my_current_job.arguments[2].ReturnStringArgument();
	float wanted_binned_pixel_size =my_current_job.arguments[3].ReturnFloatArgument();
	ProgressBar *my_progress;

	wxPrintf("\nGenerating New cisTEM Project...\n\n");

	if (warp_directory.EndsWith("/") == false) warp_directory += "/";
	if (cistem_parent_directory.EndsWith("/") == false) cistem_parent_directory += "/";
	wxString wanted_folder_name = cistem_parent_directory + project_name;
	if (wxFileName::Exists(wanted_folder_name))
	{
		SendErrorAndCrash("Database directory should not already exist, and does!\n");
	}
	else wxFileName::Mkdir(wanted_folder_name);
	wxFileName wanted_database_file = wanted_folder_name + "/" + project_name + ".db";


	Project new_project = Project();
	new_project.CreateNewProject(wanted_database_file, wanted_folder_name, project_name);
	wxPrintf(wanted_database_file.GetFullPath()+"\n");
	wxPrintf("\nSuccessfully made project database\n\n");
	wxPrintf("\nImporting Movies into new cisTEM Project...\n\n");

	wxArrayString all_files;
	wxDir::GetAllFiles 	( warp_directory, &all_files, "*.mrc", wxDIR_FILES);
	wxDir::GetAllFiles 	( warp_directory, &all_files, "*.mrcs", wxDIR_FILES);
	wxDir::GetAllFiles 	( warp_directory, &all_files, "*.tif", wxDIR_FILES);
	all_files.Sort();
	wxXmlDocument doc;
	size_t number_of_files = all_files.GetCount();

	if (all_files.IsEmpty() == true) {SendErrorAndCrash("No movies were detected in the warp directory.");}
	my_progress = new ProgressBar(number_of_files);
	new_project.database.BeginMovieAssetInsert();
	for (unsigned long counter = 0; counter < all_files.GetCount(); counter++)
	{
		size_t split_point = all_files.Item(counter).find_last_of(".");
		wxString xml_filename = all_files.Item(counter);
		xml_filename = xml_filename.Mid(0, split_point);
		xml_filename.Append(".xml");
		if (wxFileName::Exists(xml_filename) && doc.Load(xml_filename) && doc.IsOk())
		{
			MovieAsset new_asset = LoadMovieFromWarp(doc, warp_directory, all_files.Item(counter), counter, wanted_binned_pixel_size);
			new_project.database.AddNextMovieAsset(new_asset.asset_id, new_asset.asset_name, new_asset.filename.GetFullPath(), 1, new_asset.x_size, new_asset.y_size, new_asset.number_of_frames, new_asset.microscope_voltage, new_asset.pixel_size, new_asset.dose_per_frame, new_asset.spherical_aberration,new_asset.gain_filename,new_asset.dark_filename, new_asset.output_binning_factor, new_asset.correct_mag_distortion, new_asset.mag_distortion_angle, new_asset.mag_distortion_major_scale, new_asset.mag_distortion_minor_scale, new_asset.protein_is_white);
		}
		else wxPrintf("Couldn't find a warp xml output for movie " + all_files.Item(counter) + "\n");
		my_progress->Update(counter+1);
	}
	new_project.database.EndMovieAssetInsert();
	delete my_progress;
	wxPrintf("\nSuccessfully imported movies\n\n");
//	Todo motion corrected image import
	wxPrintf("\nDone with database operations. cisTEM project ready to be loaded by GUI.\n");

	return true;
}
