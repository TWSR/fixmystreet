describe('Regression tests', function() {
    it('Shows the sub-map links after clicking Try again', function() {
        cy.viewport(480, 800);
        cy.visit('/around?pc=BS10+5EE&js=1');
        cy.get('#loading-indicator').should('be.hidden'); // Work around a race bug to fix later
        cy.get('#map_box').click(200, 200);
        cy.get('#map_box image').last().trigger('mousemove').should('have.css', 'opacity', '1');
        cy.get('#try_again').click();
        cy.get('#sub_map_links').should('be.visible');
    });
});
