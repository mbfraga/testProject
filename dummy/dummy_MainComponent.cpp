#include <dummy_MainComponent.h>

#include <dummy_DropDown.h>

namespace dummy {

//== MainComponent ==================================================

MainComponent::MainComponent(QWidget *parent) : QWidget(parent)
{
}

MainComponent::~MainComponent()
{

}

void MainComponent::start()
{
    auto view = new dummy::DropDownListBox(nullptr);
    view->showDropDown({}, this);
}

}  // namespace dummy
