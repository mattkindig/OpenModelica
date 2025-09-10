/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-CurrentYear, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 LICENSE OR
 * THIS OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
 * RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
 * ACCORDING TO RECIPIENTS CHOICE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from OSMC, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or
 * http://www.openmodelica.org, and in the OpenModelica distribution.
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

#include "PlotWindowContainer.h"
#include "OutputTable.h"

using namespace OMPlot;

PlotWindowContainer::PlotWindowContainer(PlotMainWindow *pParent)
  : QMdiArea(pParent)
{
  mpPlotMainWindow = pParent;
  setActivationOrder(QMdiArea::CreationOrder);
  setHorizontalScrollBarPolicy(Qt::ScrollBarAsNeeded);
  setVerticalScrollBarPolicy(Qt::ScrollBarAsNeeded);
  setViewMode(QMdiArea::TabbedView);
}

PlotMainWindow* PlotWindowContainer::getPlotMainWindow()
{
  return mpPlotMainWindow;
}

QString PlotWindowContainer::getUniqueName(QString name, int number)
{
  QString newName;
  newName = name + QString::number(number);

  foreach (QMdiSubWindow *pWindow, subWindowList()) {
    PlotWindow *pPlotWindow = qobject_cast<PlotWindow*>(pWindow->widget());
    if (pPlotWindow->windowTitle().compare(newName) == 0) {
      newName = getUniqueName(name, ++number);
      break;
    }
  }
  return newName;
}

ResultWindow* PlotWindowContainer::getCurrentWindow()
{
  if (subWindowList(QMdiArea::ActivationHistoryOrder).size() == 0) {
    return 0;
  } else {
    return qobject_cast<ResultWindow*>(subWindowList(QMdiArea::ActivationHistoryOrder).last()->widget());
  }
}

void PlotWindowContainer::addPlotWindow(QStringList arguments)
{
  QMainWindow* pWindow = nullptr;
  if (arguments[4].compare("table", Qt::CaseInsensitive) == 0) {
      QString filename = arguments[1];
      QStringList variables = arguments.mid(22, -1);
      TableWindow *pTableWindow = new TableWindow(filename, variables, this, false);
      pTableWindow->setWindowTitle(QString(getUniqueName("Table")));
      pWindow = qobject_cast<QMainWindow*>(pTableWindow);
  } else {
      PlotWindow* pPlotWindow = new PlotWindow(arguments, this);
      if (pPlotWindow->isPlot() || pPlotWindow->isPlotAll()) {
          pPlotWindow->setWindowTitle(QString(getUniqueName()).append(" - x(t)"));
      } else {
          pPlotWindow->setWindowTitle(QString(getUniqueName()).append(" - x(y)"));
      }
      pWindow = qobject_cast<QMainWindow*>(pPlotWindow);
  }
  connect(pWindow, SIGNAL(closingDown()), SLOT(checkSubWindows()));
  setActiveSubWindow(addSubWindow(pWindow));
  if (viewMode() == QMdiArea::TabbedView) {
      pWindow->showMaximized();
  } else {
      pWindow->show();
  }
  getPlotMainWindow()->activateWindow();
}

void PlotWindowContainer::updateCurrentWindow(QStringList arguments)
{
  ResultWindow* pWindow = getCurrentWindow();
  if (pWindow) {
      pWindow->receiveMessage(arguments);
      getPlotMainWindow()->activateWindow();
  }
}

void PlotWindowContainer::checkSubWindows()
{
  if (subWindowList().size() < 2) {
    getPlotMainWindow()->close();
  }
}
