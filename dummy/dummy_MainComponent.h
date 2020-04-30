#pragma once

#include <QWidget>
namespace dummy {

//== MainComponent ==================================================
/// This class defines a way to ...
class MainComponent : public QWidget
{
    Q_OBJECT
public:
    /// Constructor
    explicit MainComponent(QWidget *parent = nullptr);

    /// Destructor
    virtual ~MainComponent() override;

    void start();
};

}  // namespace dummy
