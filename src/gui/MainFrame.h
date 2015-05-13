#ifndef __MainFrame__
#define __MainFrame__

/**
@file
Subclass of MainFrame, which is generated by wxFormBuilder.
*/

#include "ProjectX_gui.h"
#include "MovieAssetPanel.h"
#include "AlignMoviesPanel.h"

//// end generated include

/** Implementing MainFrame */
class MyMainFrame : public MainFrame
{
	public:
		/** Constructor */
		MyMainFrame( wxWindow* parent );
	//// end generated class members

		wxTreeItemId tree_root;
		wxTreeItemId movie_branch;

		void RecalculateAssetBrowser(void);
		void OnCollapseAll( wxCommandEvent& event );
		void OnMenuBookChange( wxListbookEvent& event );
	
};

#endif // __MainFrame__