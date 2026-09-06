// 
import { render, screen } from '@testing-library/react'; 
import App from './App'; 

test('renders AWS 3-TIER WEB APP DEMO', () => { render(<App />); const headingElement = screen.getByText(/AWS 3-TIER WEB APP DEMO/i); expect(headingElement).toBeInTheDocument(); });