#include <QApplication>
#include <QtWidgets>

#include <dummy_MainComponent.h>

int main(int argc, char* argv[])
{
  QApplication app(argc, argv);

  dummy::MainComponent mc;
  mc.show();

  mc.start();

  return app.exec();
}
