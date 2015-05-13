#ifndef __AlignMoviesPanel__
#define __AlignMoviesPanel__

/**
@file
Subclass of AlignMoviesPanel, which is generated by wxFormBuilder.
*/

#include "ProjectX_gui.h"
#include "MovieAssetPanel.h"
#include "mathplot.h"
#include <wx/log.h>


#ifdef DEBUG
#define MyDebugPrint(...)	wxLogDebug(__VA_ARGS__); wxPrintf("From %s:%i\n%s\n", __FILE__,__LINE__,__PRETTY_FUNCTION__);
#else
#define MyDebugPrint(...)
#endif
//// end generated include

/** Implementing AlignMoviesPanel */
class MyAlignMoviesPanel : public AlignMoviesPanel
{

		bool show_expert_options;

public:
		/** Constructor */
		MyAlignMoviesPanel( wxWindow* parent );
	//// end generated class members

		mpWindow        *plot_window;
		//mpInfoCoords    *nfo;

		std::vector<double> accumulated_dose_data;
		std::vector<double> average_movement_data;



		// methods

		void OnExpertOptionsToggle( wxCommandEvent& event );
		void OnStartAlignmentButtonUpdateUI( wxUpdateUIEvent& event );
		void FillGroupComboBox();
};

#endif // __AlignMoviesPanel__