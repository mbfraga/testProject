#pragma once

#include <QAbstractListModel>
#include <vector>

class QListView;

namespace dummy {

//== DropDownListBox ==================================================
/// This class defines a way to ...
class DropDownListBox : public QAbstractListModel {
  Q_OBJECT
public:
  /// Constructor
  explicit DropDownListBox(QObject *parent = nullptr);

  /// Destructor
  virtual ~DropDownListBox() override;

  void showDropDown(const std::vector<std::string> &matches, QWidget *parent);

  void hideDropDown();

  // QAbstractItemModel methods
  int rowCount(const QModelIndex &parent) const override;
  QVariant data(const QModelIndex &index, int role) const override;

  // QObject methods
  bool eventFilter(QObject *watched, QEvent *event) override;
  bool event(QEvent *event) override;

private:
  QListView *mListView = nullptr;
  std::vector<std::string> mMatches;
};

}
