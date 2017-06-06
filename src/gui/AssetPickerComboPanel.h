#ifndef __ASSETPICKERCOMBO_PANEL_H__
#define	__ASSETPICKERCOMBO_PANEL_H__

class AssetPickerComboPanel : public AssetPickerComboPanelParent
{
public :

	AssetPickerComboPanel(wxWindow* parent, wxWindowID id = wxID_ANY, const wxPoint& pos = wxDefaultPosition, const wxSize& size = wxDefaultSize, long style = wxTAB_TRAVERSAL);
	void ParentPopUpSelectorClicked(wxCommandEvent& event);

	void SetSelection(int wanted_selection) {AssetComboBox->SetSelection(wanted_selection);}
	void SetSelectionWithEvent(int wanted_selection)
	{
		if (wanted_selection > 0 && wanted_selection < AssetComboBox->GetCount())
		{
			AssetComboBox->SetSelection(wanted_selection);
		 	wxCommandEvent *change_event = new wxCommandEvent(wxEVT_COMBOBOX);
		 	AssetComboBox->GetEventHandler()->QueueEvent(change_event);
		}
	}
	int ReturnSelection() {return AssetComboBox->GetSelection();}
	int GetSelection() {return AssetComboBox->GetSelection();}
	int GetCount() {return AssetComboBox->GetCount();}
	void Clear() {AssetComboBox->Clear();}
	void ChangeValue(wxString value_to_set) {AssetComboBox->ChangeValue(value_to_set);}
	virtual void GetAssetFromPopup();
	//virtual bool FillComboBox() = 0;

};

class VolumeAssetPickerComboPanel : public AssetPickerComboPanel
{
public:
	VolumeAssetPickerComboPanel(wxWindow* parent, wxWindowID id = wxID_ANY, const wxPoint& pos = wxDefaultPosition, const wxSize& size = wxDefaultSize, long style = wxTAB_TRAVERSAL);
	bool FillComboBox(bool include_generate_from_params=false) {AssetComboBox->FillWithVolumeAssets(include_generate_from_params);}
};

class RefinementPackagePickerComboPanel : public AssetPickerComboPanel
{
public:
	RefinementPackagePickerComboPanel(wxWindow* parent, wxWindowID id = wxID_ANY, const wxPoint& pos = wxDefaultPosition, const wxSize& size = wxDefaultSize, long style = wxTAB_TRAVERSAL);
	bool FillComboBox() {AssetComboBox->FillWithRefinementPackages();}
};

class RefinementPickerComboPanel : public AssetPickerComboPanel
{
public:

	RefinementPickerComboPanel(wxWindow* parent, wxWindowID id = wxID_ANY, const wxPoint& pos = wxDefaultPosition, const wxSize& size = wxDefaultSize, long style = wxTAB_TRAVERSAL);
	bool FillComboBox(long wanted_refinement_package) {AssetComboBox->FillWithRefinements(wanted_refinement_package);}
};

class ClassificationPickerComboPanel : public AssetPickerComboPanel
{
public:

	ClassificationPickerComboPanel(wxWindow* parent, wxWindowID id = wxID_ANY, const wxPoint& pos = wxDefaultPosition, const wxSize& size = wxDefaultSize, long style = wxTAB_TRAVERSAL);
	bool FillComboBox(long wanted_refinement_package, bool include_new_classification) {AssetComboBox->FillWithClassifications(wanted_refinement_package, include_new_classification);}
};

class ImageGroupPickerComboPanel : public AssetPickerComboPanel
{
public:

	ImageGroupPickerComboPanel(wxWindow* parent, wxWindowID id = wxID_ANY, const wxPoint& pos = wxDefaultPosition, const wxSize& size = wxDefaultSize, long style = wxTAB_TRAVERSAL);
	bool FillComboBox(bool include_all_images_group) {AssetComboBox->FillWithImageGroups(include_all_images_group);}
};

class MovieGroupPickerComboPanel : public AssetPickerComboPanel
{
public:

	MovieGroupPickerComboPanel(wxWindow* parent, wxWindowID id = wxID_ANY, const wxPoint& pos = wxDefaultPosition, const wxSize& size = wxDefaultSize, long style = wxTAB_TRAVERSAL);
	bool FillComboBox(bool include_all_movies_group) {AssetComboBox->FillWithMovieGroups(include_all_movies_group);}
};

class ImagesPickerComboPanel : public AssetPickerComboPanel
{
public:

	ImagesPickerComboPanel(wxWindow* parent, wxWindowID id = wxID_ANY, const wxPoint& pos = wxDefaultPosition, const wxSize& size = wxDefaultSize, long style = wxTAB_TRAVERSAL);
	bool FillComboBox(long wanted_image_group) {AssetComboBox->FillWithImages(wanted_image_group);}
};



#endif